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
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
)

type CostcenterStateFieldTransition struct {
	ctx              context.Context
	cfg              *config.Config
	logger           log.Logger
	costCenterEngine engines.CostCenterEngineInterface
	customerEngine   engines.CustomerEngineInterface
	db               interfaces.Database
}

func NewCostcenterStateFieldTransition(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	costCenterEngine engines.CostCenterEngineInterface,
	customerEngine engines.CustomerEngineInterface,
	db interfaces.Database,

) *CostcenterStateFieldTransition {
	return &CostcenterStateFieldTransition{
		ctx:              ctx,
		cfg:              cfg,
		logger:           logger,
		costCenterEngine: costCenterEngine,
		customerEngine:   customerEngine,
		db:               db,
	}
}

//go:embed inputs/newFieldCostCenterState.csv
var newFieldCostcenterStatecustomerIDsFileData string

func (t *CostcenterStateFieldTransition) Run(dryRun bool, customerIDList []string, useFile bool) error {
	t.logger.Info("Started costcenterStateField transition ...")
	var customerIDs []string
	if useFile {
		t.logger.Info("Using file to get customerIDs", kvp.String("fileName", "inputs/newFieldCostcenterState.csv"))
		customerIDs = strings.Split(newFieldCostcenterStatecustomerIDsFileData, ",")
	} else {
		customerIDs = customerIDList
	}

	for _, customerID := range customerIDs {

		err := t.RunTransitionForCustomer(dryRun, customerID)
		if err != nil {
			return err
		}
		t.logger.Info("Completed costcenterStateField transition for customer", kvp.String("customerID", customerID))
		time.Sleep(1 * time.Second)
	}

	return nil
}

func (t *CostcenterStateFieldTransition) RunTransitionForCustomer(dryRun bool, customerID string) error {
	logger := t.logger.WithFields(kvp.String("customerId", customerID))
	logger.Info("Running costcenterStateField transition...")

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
		logger.WithError(bpErr.OriginalError).Error("Failed to get costcenter records.")
		return bpErr.OriginalError
	}
	logger.Info("started update", kvp.Int("costcenter count", len(costCenters)))
	if err := t.update(logger, costCenters, dryRun); err != nil {
		logger.WithError(err).Error("updateCostCenterRecords failed")
		return err
	}
	logger.Info("completed update", kvp.Int("costcenter count", len(costCenters)))

	return nil
}

func (t *CostcenterStateFieldTransition) update(logger log.Logger, costcenters []*models.CostCenter, dryRun bool) error {
	po := azcosmos.PatchOperations{}

	for _, costcenter := range costcenters {
		ccLogger := logger.WithFields(kvp.String("costcenter uuid", costcenter.Key.Id))
		ccLogger.Info("started one costcenter update")
		ccLogger.Info("started costcenter record update")
		if !dryRun {
			// update costcenter record with state field
			po.AppendAdd("/CostCenterState", models.CostCenterActive)
			po.AppendAdd("/Customer/CostCenterState", models.CostCenterActive)
			err := t.db.PatchWithOptions(t.ctx, logger, costcenter, po, nil)
			if err != nil {
				logger.WithError(err).Error("Failed to update costcenter record.")
				return err
			}
		}
		ccLogger.Info("completed costcenter record update")

		// update costcenter customer records with state field
		costcenterCustomer, err := t.customerEngine.Get(t.ctx, ccLogger, costcenter.Key.Id, false)
		if err != nil {
			logger.WithError(err).Error("Failed to get costcenter customer record.")
			return err
		}
		ccLogger.Info("started costcenter customer record update")
		if !dryRun {
			po = azcosmos.PatchOperations{}
			po.AppendAdd("/CostCenterState", models.CostCenterActive)
			err = t.db.PatchWithOptions(t.ctx, ccLogger, costcenterCustomer, po, nil)
			if err != nil {
				logger.WithError(err).Error("Failed to update costcenter customer record.")
				return err
			}
		}
		ccLogger.Info("completed costcenter customer record update")

		// update resources associated with this costcenter
		if err = t.updateLookUpResources(*costcenter, ccLogger, dryRun); err != nil {
			return err
		}

		if err = t.updateByTargetRecords(*costcenter, ccLogger, dryRun); err != nil {
			return err
		}
		// sleep for 1 second to avoid rate limiting
		time.Sleep(1 * time.Second)
		ccLogger.Info("completed one costcenter update")
	}

	logger.Info("completed costcenterStateField transition.")
	return nil
}

func (t *CostcenterStateFieldTransition) updateLookUpResources(costcenter models.CostCenter, logger log.Logger, dryRun bool) error {

	querier := db.NewQuerier[*models.CostCenter](t.db)

	queryString := fmt.Sprintf("select * from c where c.UUID=\"%s\" and c.id LIKE \"resourceLookup:%%\" ", costcenter.Key.Id)
	costcenterResources, err := querier.QueryItems(t.ctx, logger, queryString, costcenter.PartitionKey)
	if err != nil {
		logger.WithError(err).Error("Unable to find any resourceLookup records")
		return err
	}
	logger.Info("started resource record update", kvp.Int("resourceLookup count", len(costcenterResources)))

	err = patchResource(costcenterResources, logger, t, dryRun)

	logger.Info("completed resource record update", kvp.Int("resourceLookup count", len(costcenterResources)))

	return err

}

func (t *CostcenterStateFieldTransition) updateByTargetRecords(costcenter models.CostCenter, logger log.Logger, dryRun bool) error {

	querier := db.NewQuerier[*models.CostCenter](t.db)

	queryString := fmt.Sprintf("select * from c where c.UUID=\"%s\" and c.id LIKE \"byTarget:%%\"", costcenter.Key.Id)
	costcenterTargets, err := querier.QueryItems(t.ctx, logger, queryString, costcenter.PartitionKey)
	if err != nil {
		logger.WithError(err).Error("Unable to find any targetby records")
		return err
	}
	logger.Info("started by target record update", kvp.Int("byTarget count", len(costcenterTargets)))
	err = patchResource(costcenterTargets, logger, t, dryRun)

	logger.Info("completed by target record update", kvp.Int("byTarget count", len(costcenterTargets)))
	return err
}

func patchResource(costcenterResources []*models.CostCenter, logger log.Logger, t *CostcenterStateFieldTransition, dryRun bool) error {
	for _, costcenterResource := range costcenterResources {
		logger = logger.WithFields(kvp.String("costcenterResourceId", costcenterResource.Key.Id))
		logger.Info("started resource/target record update")
		if !dryRun {
			po := azcosmos.PatchOperations{}
			po.AppendAdd("/CostCenterState", models.CostCenterActive)
			po.AppendAdd("/Customer/CostCenterState", models.CostCenterActive)

			err := t.db.PatchWithOptions(t.ctx, logger, costcenterResource, po, nil)
			if err != nil {
				logger.WithError(err).Error("Failed to update costcenter resource record.")
				return err
			}
		}
		logger.Info("completed resource/target record update")
		// sleep for 1 second to avoid rate limiting
		time.Sleep(1 * time.Second)
	}

	return nil
}
