package transitions

import (
	"context"
	_ "embed"
	"fmt"
	"strings"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

//go:embed inputs/removeByTargetCostCenter.csv
var customerIDsFileData string

type RemoveByTargetCostCenterDocs struct {
	ctx              context.Context
	cfg              *config.Config
	logger           log.Logger
	costCenterEngine engines.CostCenterEngineInterface
	customerEngine   engines.CustomerEngineInterface
	db               interfaces.Database
}

func NewRemoveByTargetCostCenterDocs(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	costCenterEngine engines.CostCenterEngineInterface,
	customerEngine engines.CustomerEngineInterface,
	db interfaces.Database,
) *RemoveByTargetCostCenterDocs {
	return &RemoveByTargetCostCenterDocs{
		ctx:              ctx,
		cfg:              cfg,
		logger:           logger,
		costCenterEngine: costCenterEngine,
		customerEngine:   customerEngine,
		db:               db,
	}
}

func (t *RemoveByTargetCostCenterDocs) Run(dryRun bool, customerIDList []string, useFile bool) error {
	t.logger.Info("Started RemoveByTargetCostCenterDocs transition ...")
	var customerIDs []string
	if useFile {
		t.logger.Info("Using file to get customerIDs", kvp.String("fileName", "inputs/removeByTargetCostCenter.csv"))
		customerIDsFileData = strings.TrimSuffix(customerIDsFileData, "\n")
		customerIDs = strings.Split(customerIDsFileData, ",")
	} else {
		customerIDs = customerIDList
	}
	for _, customerID := range customerIDs {
		err := t.RunTransitionForCustomer(dryRun, customerID)
		if err != nil {
			t.logger.Error("Failed to run transition for customer", kvp.String("customerID", customerID))
			continue
		}
		t.logger.Info("Successfully completed costcenterStateField transition for customer", kvp.String("customerID", customerID))
		time.Sleep(1 * time.Second)
	}

	return nil
}

func (t *RemoveByTargetCostCenterDocs) RunTransitionForCustomer(dryRun bool, customerID string) error {
	logger := t.logger.WithFields(kvp.String("customerId", customerID))
	logger.Info("Running RemoveByTargetCostCenterDocs transition...")

	customer, err := t.customerEngine.Get(t.ctx, logger, customerID, false)
	if err != nil {
		logger.WithError(err).Error("Failed to get customer record.")
		return err
	}

	if customer == nil {
		logger.Error("Customer not found.")
		return fmt.Errorf("customer not found: %s", customerID)
	}

	// TODO: Replace all occurrences of 'bpErr' with 'err' to handle errors throughout the code.
	// we will replace the standard error package with the bperrors package and use
	// the err variable to handle errors throughout the code.
	costCenters, bpErr := t.costCenterEngine.GetAllCostCenters(t.ctx, t.logger, customer)
	if bpErr != nil {
		logger.WithError(bpErr.OriginalError).Error(bpErr.FriendlyError.Error())
		return bpErr
	}

	logger.Info("started update", kvp.Int("costcenter count", len(costCenters)))

	return t.update(logger, costCenters, dryRun)
}

func (t *RemoveByTargetCostCenterDocs) update(logger log.Logger, costCenters []*models.CostCenter, dryRun bool) error {
	po := azcosmos.PatchOperations{}
	for _, costCenter := range costCenters {
		ccLogger := logger.WithFields(kvp.String("costcenter uuid", costCenter.Key.Id))
		if costCenter.CostCenterState == models.CostCenterArchived {
			continue
		}
		ccLogger.Info("Processing costcenter")
		if costCenter.TargetType == models.ZuoraSubscription {
			ccLogger.Info("Deleting zuora Target Type document", kvp.String("targetId", costCenter.AsTargetType().Id))
			if !dryRun {
				err := t.db.DeleteWithOptions(t.ctx, t.logger, costCenter.AsTargetType(), nil)
				if err != nil {
					ccLogger.WithError(err).Error("Failed to zuora delete target type document", kvp.String("targetId", costCenter.AsTargetType().Id))
					continue
				}
			}

		} else {
			// Handle azure subscription
			// Move azure subscription id on the target type document to the cost center document
			hasTargetDoc, err := t.db.Exists(t.ctx, t.logger, costCenter.AsTargetType(), nil)
			if err != nil {
				ccLogger.WithError(err).Error("Failed to check if azure target type document exists.")
			}
			if !hasTargetDoc {
				ccLogger.Info("No azure target type document exists")
				continue
			}
			targetTypeDocument, err := t.costCenterEngine.Get(t.ctx, logger, costCenter.AsTargetType())

			if err != nil {
				ccLogger.WithError(err).Error("Failed to get azure target type document.")
				continue
			}
			if targetTypeDocument == nil {
				ccLogger.Info("No azure target type document found for costcenter")
				continue
			}
			if targetTypeDocument.UUID != costCenter.UUID {
				ccLogger.Info("No azure target type document found for costcenter")
				continue
			}
			// set the azure subscription id on the cost center document from the target type partition doc id
			azureSubscriptionIdFromPartitionId := strings.Split(targetTypeDocument.Id, ":")[2]
			if azureSubscriptionIdFromPartitionId != costCenter.TargetId {
				ccLogger.Info("Updating azure target Id on costcenter", kvp.String("targetId", costCenter.TargetId), kvp.String("newTargetId", azureSubscriptionIdFromPartitionId))

				po.AppendSet("/targetId", azureSubscriptionIdFromPartitionId)
				if !dryRun {
					err := t.db.PatchWithOptions(t.ctx, logger, costCenter, po, nil)
					if err != nil {
						ccLogger.WithError(err).Error("Failed to update azure target Id on costcenter", kvp.String("targetId", costCenter.AsTargetType().Id))
						return err
					}
				}
			}
			// delete the target type document
			ccLogger.Info("Deleting Target Type document", kvp.String("Id", costCenter.AsTargetType().Id))
			if !dryRun {
				err = t.db.DeleteWithOptions(t.ctx, t.logger, costCenter.AsTargetType(), nil)
				if err != nil {
					ccLogger.WithError(err).Error("Failed to delete azure target type document", kvp.String("targetId", costCenter.AsTargetType().Id))
					return err
				}
			}
		}
	}
	return nil
}
