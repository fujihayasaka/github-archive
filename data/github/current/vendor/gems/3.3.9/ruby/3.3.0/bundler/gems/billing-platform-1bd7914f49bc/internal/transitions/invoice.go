package transitions

import (
	"context"
	"time"

	"github.com/github/billing-platform/lib/azurecommerce"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/data"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/log"
)

type InvoiceBackfillTransition struct {
	ctx                 context.Context
	cfg                 *config.Config
	logger              log.Logger
	ac                  *azurecommerce.AzureCommerce
	azureEmissionEngine *engines.AzureEmissionEngine
	customerEngine      *engines.CustomerEngine
	costCenterEngine    engines.CostCenterEngineInterface
	usageEngine         *engines.UsageEngine
	dataService         *data.DataService
}

func NewInvoiceBackfillTransition(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	ac *azurecommerce.AzureCommerce,
	azureEmissionEngine *engines.AzureEmissionEngine,
	customerEngine *engines.CustomerEngine,
	costCenterEngine engines.CostCenterEngineInterface,
	usageEngine *engines.UsageEngine,
	dataService *data.DataService,
) *InvoiceBackfillTransition {
	return &InvoiceBackfillTransition{
		ctx:                 ctx,
		cfg:                 cfg,
		logger:              logger,
		ac:                  ac,
		azureEmissionEngine: azureEmissionEngine,
		customerEngine:      customerEngine,
		costCenterEngine:    costCenterEngine,
		usageEngine:         usageEngine,
		dataService:         dataService,
	}
}

func (t *InvoiceBackfillTransition) Run(dryRun bool) error {
	t.logger.Info("Running invoice transition...")

	err := t.GetAndPublishInvoice(dryRun, time.August)
	if err != nil {
		return err
	}

	err = t.GetAndPublishInvoice(dryRun, time.September)
	if err != nil {
		return err
	}

	return nil
}

func (t *InvoiceBackfillTransition) GetAndPublishInvoice(dryRun bool, month time.Month) error {
	var days int
	if month == time.September {
		// the day in which we started to emit invoices to Kusto
		days = 5
	} else {
		days = 31
	}

	for i := 1; i <= days; i++ {
		partitionDetail := &models.UsagePartitionDetail{
			UsageTime:  models.NewUsageTime().WithYear(2023).WithMonthInt(int64(month)).WithDay(i),
			ActiveType: models.Daily,
		}

		azureUsageItems, err := t.azureEmissionEngine.GetAzureUsageItems(t.ctx, t.logger, partitionDetail)
		switch {
		case err != nil:
			return err
		case len(azureUsageItems) == 0:
			t.logger.Info("no azure usage items found")
			continue
		default:
			for _, azureUsageItem := range azureUsageItems {
				azureEmissionPartitionDetail := &models.AzureEmissionPartitionDetail{
					CustomerId: azureUsageItem.GetCustomerId(),
					Sku:        azureUsageItem.GetSku(),
					Year:       int64(2023),
					Month:      int64(month),
					Day:        int64(i),
				}

				azureEmission, err := t.azureEmissionEngine.GetAzureEmission(t.ctx, t.logger, azureEmissionPartitionDetail)

				switch {
				case err != nil:
					t.logger.WithError(err).Error("failed to get azure emission")
				case azureEmission != nil && azureEmission.Status != models.AzureEmissionFailed:
					t.logger.Info("Publishing azure invoice message...")

					billingCustomer, parentCustomer, err := t.customerEngine.GetBillingAndParentCustomersFromCustomerId(t.ctx, t.logger, azureUsageItem.GetCustomerId())
					if err != nil {
						return err
					}
					// EnterpriseInfo represents either the parent enterprise, or the cost center customer if it exists.
					// We want to use whichever azureAccountId exists, either the parent or cost center's
					enterpriseInfo := t.customerEngine.GetEnterpriseInfoFromBillingAndParentCustomers(t.ctx, t.logger, billingCustomer, parentCustomer)

					t.dataService.PublishAzureInvoiceMessage(t.ctx, t.logger, enterpriseInfo, azureUsageItem, azureEmission, dryRun)
				default:
					if azureEmission == nil {
						t.logger.Info("azure emission not found")
					} else {
						t.logger.Info("azure emission failed")
					}

				}
			}

		}
	}

	return nil
}
