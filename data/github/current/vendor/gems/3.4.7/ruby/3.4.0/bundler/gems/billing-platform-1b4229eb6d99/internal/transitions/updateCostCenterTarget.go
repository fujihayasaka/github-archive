package transitions

import (
	"context"
	_ "embed"
	"fmt"
	"strings"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"

	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
)

type UpdateCostCenterTargetTransition struct {
	ctx              context.Context
	cfg              *config.Config
	logger           log.Logger
	costCenterEngine engines.CostCenterEngineInterface
	customerEngine   engines.CustomerEngineInterface
	db               interfaces.Database
}

func NewUpdateCostCenterTargetTransition(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	costCenterEngine engines.CostCenterEngineInterface,
	customerEngine engines.CustomerEngineInterface,
	db interfaces.Database,

) *UpdateCostCenterTargetTransition {
	return &UpdateCostCenterTargetTransition{
		ctx:              ctx,
		cfg:              cfg,
		logger:           logger,
		costCenterEngine: costCenterEngine,
		customerEngine:   customerEngine,
		db:               db,
	}
}

//go:embed inputs/costCenterEnterprises.csv
var allEnterprisesWithCostCenterscustomerIDsFileData string

func (t *UpdateCostCenterTargetTransition) Run(dryRun bool, customerIDList []string, useFile bool) error {
	t.logger.Info("Started UpdateCostCenterTargetTransition ...")
	var customerIDs []string
	if useFile {
		t.logger.Info("Using file to get customerIDs", kvp.String("fileName", "inputs/costCenterEnterprises.csv"))
		customerIDs = strings.Split(allEnterprisesWithCostCenterscustomerIDsFileData, ",")
	} else {
		customerIDs = customerIDList
	}

	for _, customerID := range customerIDs {

		err := t.RunTransitionForCustomer(dryRun, customerID)
		if err != nil {
			return err
		}
		t.logger.Info("Completed UpdateCostCenterTargetTransition for customer", kvp.String("customerID", customerID))
		time.Sleep(1 * time.Second)
	}

	return nil
}

func (t *UpdateCostCenterTargetTransition) RunTransitionForCustomer(dryRun bool, customerID string) error {
	logger := t.logger.WithFields(kvp.String("gh.billing_platform.transition.customerId", customerID))
	logger.Info("Started updateCostCenterTarget transition...")

	customer, err := t.customerEngine.Get(t.ctx, t.logger, customerID, false)
	if err != nil {
		logger.WithError(err).Error("Failed to get customer record.")
		return err
	}

	if customer == nil {
		logger.Error("Customer not found.")
		return fmt.Errorf("customer not found: %s", customerID)
	}

	costCenters, bpErr := t.costCenterEngine.GetAllCostCenters(t.ctx, t.logger, customer)
	if bpErr != nil {
		logger.WithError(bpErr.OriginalError).Error(bpErr.FriendlyError.Error())
		return bpErr
	}

	logger.Info("Cost centers found", kvp.Int("gh.billing_platform.transition.costCenterCount", len(costCenters)))

	for _, costCenter := range costCenters {
		logger := t.logger.WithFields(kvp.String("gh.billing_platform.transition.costCenterUuid", costCenter.CostCenterKey.UUID))
		logger.Info("Starting cost center target update...")

		costCenterCustomer, err := t.customerEngine.Get(t.ctx, t.logger, costCenter.CostCenterKey.UUID, false)
		if err != nil {
			logger.WithError(err).Error("Failed to get cost center customer")
			return err
		}

		if costCenterCustomer == nil {
			logger.Error("Cost center customer not found.")
			return fmt.Errorf("cost center customer not found: %s", costCenter.CostCenterKey.UUID)
		}

		if !t.NeedsABillingTargetUpdate(logger, costCenter, customer, costCenterCustomer) {
			logger.Info("No billing target update needed. Skipping...")
			continue
		}

		err = t.UpdateCostCenterCustomerTarget(dryRun, customer, costCenterCustomer)
		if err != nil {
			return err
		}

		err = t.UpdateCostCenterTarget(dryRun, customer, costCenter)
		if err != nil {
			return err
		}

		err = t.UpdateCostCenterTargetOnResources(dryRun, customer, costCenter)
		if err != nil {
			return err
		}
		logger.Info("Completed cost center target update...")
	}

	logger.Info("Finished running updateCostCenterTarget transition")

	return nil
}

func (t *UpdateCostCenterTargetTransition) NeedsABillingTargetUpdate(logger log.Logger, costCenter *models.CostCenter, enterprise *models.Customer, costCenterCustomer *models.Customer) bool {
	if costCenter.CostCenterState == models.CostCenterArchived {
		logger.Info("Cost center is archived. Skipping...")
		return false
	}
	if enterprise.BillingTarget == costCenterCustomer.BillingTarget {
		if enterprise.BillingTarget == models.Azure {
			if costCenter.TargetType == models.AzureSubscription {
				logger.Info("Enterprise billing target is the same as the cost center customer billing target. Skipping...")
				return false
			}
		} else if enterprise.BillingTarget == models.Zuora {
			if costCenter.TargetType == models.ZuoraSubscription {
				logger.Info("Enterprise billing target is the same as the cost center customer billing target. Skipping...")
				return false
			}
		}
	}

	return true

}

func (t *UpdateCostCenterTargetTransition) UpdateCostCenterCustomerTarget(dryRun bool, customer *models.Customer, costCenterCustomer *models.Customer) error {
	logger := t.logger.WithFields(
		kvp.String("gh.billing_platform.transition.customerId", customer.GetCustomerId()),
		kvp.String("gh.billing_platform.transition.customerBillingTarget", customer.BillingTarget.ToProto().String()),
		kvp.String("gh.billing_platform.transition.costCenterUuid", costCenterCustomer.GetCustomerId()),
		kvp.String("gh.billing_platform.transition.costCenterBillingTarget", costCenterCustomer.BillingTarget.ToProto().String()))
	logger.Info("Running UpdateCostCenterCustomerTarget...")

	if dryRun {
		logger.Info("Dry run mode. Skipping update.")
	} else {
		po := azcosmos.PatchOperations{}
		po.AppendAdd("/BillingTarget", customer.BillingTarget)

		err := t.db.PatchWithOptions(t.ctx, logger, costCenterCustomer, po, nil)
		if err != nil {
			logger.WithError(err).Error("Failed to update cost center customer record.")
			return err
		}

		logger.Info("Updated cost center customer record.")
	}

	return nil
}

func (t *UpdateCostCenterTargetTransition) UpdateCostCenterTarget(dryRun bool, customer *models.Customer, costCenter *models.CostCenter) error {
	logger := t.logger.WithFields(
		kvp.String("gh.billing_platform.transition.customerId", customer.GetCustomerId()),
		kvp.String("gh.billing_platform.transition.customerBillingTarget", customer.BillingTarget.ToProto().String()),
		kvp.String("gh.billing_platform.transition.costCenterUuid", costCenter.CostCenterKey.UUID),
		kvp.String("gh.billing_platform.transition.costCenterTargetType", costCenter.TargetType.ToProto().String()))
	logger.Info("Running UpdateCostCenterTarget...")

	if dryRun {
		logger.Info("Dry run mode. Skipping update.")
	} else {
		po := azcosmos.PatchOperations{}

		if customer.BillingTarget == models.Azure {
			po.AppendAdd("/TargetType", models.AzureSubscription)
		} else if customer.BillingTarget == models.Zuora {
			po.AppendAdd("/TargetType", models.ZuoraSubscription)
		}

		// Cleaning the target id to prevent a mismatch between Azure and Zuora.
		// This will default to the customer billing target.
		po.AppendAdd("/TargetId", "")

		// Updating the billing target on the embedded customer object.
		po.AppendAdd("/Customer/BillingTarget", customer.BillingTarget)

		err := t.db.PatchWithOptions(t.ctx, logger, costCenter, po, nil)
		if err != nil {
			logger.WithError(err).Error("Failed to update cost center record.")
			return err
		}

		logger.Info("Updated cost center record.")
	}

	return nil
}

func (t *UpdateCostCenterTargetTransition) UpdateCostCenterTargetOnResources(dryRun bool, customer *models.Customer, costCenter *models.CostCenter) error {
	logger := t.logger.WithFields(
		kvp.String("gh.billing_platform.transition.customerId", customer.GetCustomerId()),
		kvp.String("gh.billing_platform.transition.customerBillingTarget", customer.BillingTarget.ToProto().String()),
		kvp.String("gh.billing_platform.transition.costCenterUuid", costCenter.CostCenterKey.UUID),
		kvp.Int("gh.billing_platform.transition.costCenterResourcesCount", len(costCenter.Resources)))
	logger.Info("Running UpdateCostCenterTargetOnResources...")

	if dryRun {
		for _, resource := range costCenter.Resources {
			resourceLookup := costCenter.AsResourceLookup(resource)
			logger.WithFields(
				kvp.String("gh.billing_platform.transition.resourceId", resourceLookup.Id),
				kvp.String("gh.billing_platform.transition.resourceTargetType", resourceLookup.TargetType.ToProto().String()),
			).Info("Dry run mode. Skipping update.")
		}
	} else {
		for _, resource := range costCenter.Resources {
			resourceLookup := costCenter.AsResourceLookup(resource)
			logger.WithFields(
				kvp.String("gh.billing_platform.transition.resourceId", resourceLookup.Id),
				kvp.String("gh.billing_platform.transition.resourceTargetType", resourceLookup.TargetType.ToProto().String()),
			).Info("Updating resource...")

			po := azcosmos.PatchOperations{}

			if customer.BillingTarget == models.Azure {
				po.AppendAdd("/TargetType", models.AzureSubscription)
			} else if customer.BillingTarget == models.Zuora {
				po.AppendAdd("/TargetType", models.ZuoraSubscription)
			}

			// Cleaning the target id to prevent a mismatch between Azure and Zuora.
			// This will default to the customer billing target.
			po.AppendAdd("/TargetId", "")

			// Updating the billing target on the embedded customer object.
			po.AppendAdd("/Customer/BillingTarget", customer.BillingTarget)

			err := t.db.PatchWithOptions(t.ctx, logger, resourceLookup, po, nil)
			if err != nil {
				logger.WithError(err).Error("Failed to update cost center resource record.")
				return err
			}

			logger.Info("Updated cost center resource record.")
		}
	}

	return nil
}
