package transitions

import (
	"context"
	"fmt"
	"time"

	"github.com/github/billing-platform/internal/logging"
	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/azurecommerce"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/data"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

type EmitAzureUsageTransition struct {
	cfg                 *config.Config
	logger              log.Logger
	azureCommerce       *azurecommerce.AzureCommerce
	pricingEngine       *engines.PricingEngine
	customerEngine      *engines.CustomerEngine
	azureEmissionEngine *engines.AzureEmissionEngine
	costCenterEngine    engines.CostCenterEngineInterface
	dataService         *data.DataService
	db                  interfaces.Database
}

func NewEmitAzureUsageTransition(
	cfg *config.Config,
	logger log.Logger,
	azureCommerce *azurecommerce.AzureCommerce,
	pricingEngine *engines.PricingEngine,
	customerEngine *engines.CustomerEngine,
	azureEmissionEngine *engines.AzureEmissionEngine,
	costCenterEngine engines.CostCenterEngineInterface,
	dataService *data.DataService,
	db interfaces.Database,
) *EmitAzureUsageTransition {
	return &EmitAzureUsageTransition{
		cfg:                 cfg,
		logger:              logger,
		azureCommerce:       azureCommerce,
		pricingEngine:       pricingEngine,
		customerEngine:      customerEngine,
		costCenterEngine:    costCenterEngine,
		azureEmissionEngine: azureEmissionEngine,
		dataService:         dataService,
		db:                  db,
	}
}

func (t *EmitAzureUsageTransition) Run(ctx context.Context, dryRun bool, skipParentEnterprise bool, skipCostCenters bool) error {
	customerIDAndQuantityList := map[string]float64{
		"1061737": 0.0, // Avocado Corp.
	}

	// This list can include cost centers in any of the enterprises listed above in customerIdAndQuantityList.
	costCenterUUIDAndQuantityList := map[string]float64{
		"de8a26c1-65b8-47cc-9a7c-74caa881bcc9": 0.0, // Avocado Corp. Customer Demo
		"e83dbe85-b7dd-4205-9935-16dcdbeec040": 0.0, // Avocado Corp. Test
	}

	copilotForBusinessPricing, err := t.pricingEngine.GetPricing(ctx, t.logger, "copilot_for_business", false)
	if err != nil {
		return errors.Wrap(err, "failed to get pricing: copilot_for_business")
	}

	if copilotForBusinessPricing == nil {
		t.logger.Info("Pricing not found", kvp.String("gh.billing_platform.transition.sku", "copilot_for_business"))
		return nil
	}

	for customerID, quantity := range customerIDAndQuantityList {
		customer, err := t.customerEngine.Get(ctx, t.logger, customerID)
		if err != nil {
			return err
		}

		if customer == nil {
			t.logger.Info("Customer not found", kvp.String("transition.customerId", customerID))
			return nil
		}

		if !(skipParentEnterprise) {
			// process usage for the parent customer
			t.logger.Info("Running EmitAzureUsage transition for parent customer...",
				kvp.String(logging.BillingCustomerId, customerID),
				kvp.String("gh.billing_platform.transition.quantity", fmt.Sprintf("%f", quantity)),
				kvp.String("gh.billing_platform.transition.sku", copilotForBusinessPricing.GetSku()))

			billingCustomer, parentCustomer, err := t.customerEngine.GetBillingAndParentCustomersFromCustomerId(ctx, t.logger, customerID)
			if err != nil {
				return err
			}
			// EnterpriseInfo represents either the parent enterprise, or the cost center customer if it exists.
			// We want to use whichever azureAccountId exists, either the parent or cost center's
			enterpriseInfo := t.customerEngine.GetEnterpriseInfoFromBillingAndParentCustomers(ctx, t.logger, billingCustomer, parentCustomer)

			err = t.RunTransitionForCustomer(ctx, dryRun, customer, quantity, copilotForBusinessPricing, enterpriseInfo, nil)
			if err != nil {
				return err
			}
		}

		if !skipCostCenters {
			costCenters, bperr := t.costCenterEngine.GetAllCostCenters(ctx, t.logger, customer)
			if bperr != nil {
				return errors.New(bperr.Error())
			}

			// process usage for any cost centers in the cost center list above
			for _, costCenter := range costCenters {
				quantity, ok := costCenterUUIDAndQuantityList[costCenter.CostCenterKey.UUID]
				if ok {
					billingCustomer, parentCustomer, err := t.customerEngine.GetBillingAndParentCustomersFromCustomerId(ctx, t.logger, costCenter.UUID)
					if err != nil {
						return err
					}
					// EnterpriseInfo represents either the parent enterprise, or the cost center customer if it exists.
					// We want to use whichever azureAccountId exists, either the parent or cost center's
					enterpriseInfo := t.customerEngine.GetEnterpriseInfoFromBillingAndParentCustomers(ctx, t.logger, billingCustomer, parentCustomer)

					t.logger.Info("Running EmitAzureUsage transition...",
						kvp.String("gh.billing_platform.transition.enterpriseCustomerId", enterpriseInfo.EnterpriseCustomerId),
						kvp.String("gh.billing_platform.transition.azureSubscriptionId", enterpriseInfo.AzureAccountId),
						kvp.String("gh.billing_platform.transition.costCenterUUID", costCenter.CostCenterKey.UUID),
						kvp.String("gh.billing_platform.transition.quantity", fmt.Sprintf("%f", quantity)),
						kvp.String("gh.billing_platform.transition.sku", copilotForBusinessPricing.GetSku()))

					err = t.RunTransitionForCustomer(ctx, dryRun, customer, quantity, copilotForBusinessPricing, enterpriseInfo, costCenter)
					if err != nil {
						return err
					}
				}
			}
		}
	}

	return nil
}

func (t *EmitAzureUsageTransition) RunTransitionForCustomer(ctx context.Context, dryRun bool, customer *models.Customer, quantity float64, pricing *models.Pricing, enterpriseInfo *models.EnterpriseInfo, costCenter *models.CostCenter) error {
	amounts := &models.Amounts{
		Quantity: nano.NewFromFloat(float64(quantity)).Int64(),
	}

	usageCustomerId := t.getUsageCustomerId(costCenter, enterpriseInfo)
	costCenterDetail := t.getCostCenterDetail(costCenter, usageCustomerId)

	entityDetail := &models.EntityDetail{
		CustomerId:       enterpriseInfo.EnterpriseCustomerId,
		CostCenterDetail: costCenterDetail,
	}

	item := &models.Item{
		Amounts:      amounts,
		Pricing:      pricing,
		EntityDetail: entityDetail,
		SourceUri:    "backfill",
		UsageAt:      *models.NewUsageTimeFromTime(time.Now().UTC()),
	}

	if dryRun {
		t.logger.Info("Attempt to emit usage",
			kvp.String("usage.azureSubscriptionId", enterpriseInfo.AzureAccountId),
			kvp.String("usage.customerId", usageCustomerId),
			kvp.String("usage.sku", pricing.GetSku()),
			kvp.String("usage.quantity", fmt.Sprintf("%f", item.Amounts.ToDecimal().Quantity)),
			kvp.String("usage.usageAt", item.UsageAt.String()))
	} else {
		// Send usage to Azure Commerce
		// usageCustomerId is the enterpriseInfo.CostCenterUUID if a cost center is present, otherwise enterpriseInfo.EnterpriseCustomerId
		azureEmission, err := t.azureCommerce.EmitLineItem(ctx, stats.NullStatter, t.cfg, item, enterpriseInfo.AzureAccountId, usageCustomerId, 0)
		if err != nil {
			return errors.Wrap(err, "failed to emit azure usage")
		}

		// Update Azure emission ID to not colide with other emissions on the same day
		azureEmission.GetKey().Id = fmt.Sprintf("%s:backfill", azureEmission.GetKey().Id)

		// Save azure emission record to the database
		_, upsertErr := t.azureEmissionEngine.UpsertAzureEmission(ctx, t.logger, azureEmission)
		if upsertErr != nil {
			return errors.Wrap(upsertErr, "failed to create azure emission record")
		}

		t.dataService.PublishAzureInvoiceMessage(ctx, t.logger, enterpriseInfo, item, azureEmission, dryRun)

		t.logger.Info("Created Azure emission record",
			kvp.String("azureEmission.partitionKey", azureEmission.GetKey().PartitionKey),
			kvp.String("azureEmission.id", azureEmission.GetKey().Id),
			kvp.String("azureEmission.azurePartitionKey", azureEmission.AzurePartitionKey),
			kvp.String("azureEmission.subscriptionId", azureEmission.SubscriptionId),
			kvp.String("azureEmission.meterId", azureEmission.MeterId),
			kvp.String("azureEmission.emissionStatus", fmt.Sprintf("%d", azureEmission.Status)),
			kvp.String("azureEmission.errorMessage", azureEmission.ErrorMessage))
	}

	return nil
}

func (t *EmitAzureUsageTransition) getUsageCustomerId(costCenter *models.CostCenter, enterpriseInfo *models.EnterpriseInfo) string {
	var usageCustomerId string
	if costCenter != nil {
		usageCustomerId = enterpriseInfo.CostCenterUUID
	} else {
		usageCustomerId = enterpriseInfo.EnterpriseCustomerId
	}

	return usageCustomerId
}

func (t *EmitAzureUsageTransition) getCostCenterDetail(costCenter *models.CostCenter, enterpriseCustomerId string) *models.CostCenterDetail {
	var costCenterDetail *models.CostCenterDetail
	if costCenter != nil {
		costCenterDetail = costCenter.Customer.CostCenterDetail
	} else {
		costCenterDetail = &models.CostCenterDetail{
			EnterpriseCustomerId: enterpriseCustomerId,
		}
	}

	return costCenterDetail
}
