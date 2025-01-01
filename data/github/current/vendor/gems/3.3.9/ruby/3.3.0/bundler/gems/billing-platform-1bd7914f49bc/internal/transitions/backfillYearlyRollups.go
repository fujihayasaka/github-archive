package transitions

import (
	"context"
	_ "embed"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/internal/logging"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
	"go.uber.org/ratelimit"
)

//go:embed inputs/backfillRollupsCustomerIds.csv
var backfillYearlyRollupsCustomerIDsFileData []byte

type BackfillYearlyRollups struct {
	ctx              context.Context
	cfg              *config.Config
	logger           log.Logger
	costCenterEngine engines.CostCenterEngineInterface
	customerEngine   *engines.CustomerEngine
	usageEngine      *engines.UsageEngine
	db               interfaces.Database
}

func NewBackfillYearlyRollups(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	costCenterEngine engines.CostCenterEngineInterface,
	customerEngine *engines.CustomerEngine,
	usageEngine *engines.UsageEngine,
	db interfaces.Database,
) *BackfillYearlyRollups {
	return &BackfillYearlyRollups{
		ctx:              ctx,
		cfg:              cfg,
		logger:           logger,
		costCenterEngine: costCenterEngine,
		customerEngine:   customerEngine,
		usageEngine:      usageEngine,
		db:               db,
	}
}

func (t *BackfillYearlyRollups) Run(dryRun bool, customerIDList []string, useFile bool) error {
	t.logger.Info("Started BackfillYearlyRollups transition ...")
	var customerIDs []string
	if useFile {
		t.logger.Info("Using file to get customerIDs",
			kvp.String("gh.billing_platform.transition.file_name", "inputs/backfillRollupsCustomerIds.csv"),
			kvp.Int("gh.billing_platform.transition.file_size_in_bytes", len(backfillYearlyRollupsCustomerIDsFileData)),
		)
		backfillYearlyRollupsCustomerIDs := strings.TrimSuffix(string(backfillYearlyRollupsCustomerIDsFileData), "\n")
		customerIDs = strings.Split(backfillYearlyRollupsCustomerIDs, ",")
		t.logger.Info(fmt.Sprintf("%d customer(s) found", len(customerIDs)))
	} else {
		customerIDs = customerIDList
	}

	customerRateLimit := ratelimit.New(10) // 10 customers per second
	prev := time.Now()
	for _, customerID := range customerIDs {
		now := customerRateLimit.Take()
		logger := t.logger.WithFields(kvp.String(logging.BillingCustomerId, customerID))
		err := t.RunTransitionForCustomer(dryRun, customerID)
		if err != nil {
			logger.WithError(err).Error("Failed to run transition for customer")
			continue
		}
		logger.Info("Successfully completed BackfillYearlyRollups transition for customer")
		logger.Info(fmt.Sprintf("Duration: %s", now.Sub(prev)))
		prev = now
	}

	return nil
}

func (t *BackfillYearlyRollups) RunTransitionForCustomer(dryRun bool, customerID string) error {
	logger := t.logger.WithFields(kvp.String(logging.BillingCustomerId, customerID))
	logger.Info("Running BackfillYearlyRollups transition...")

	customer, err := t.customerEngine.Get(t.ctx, logger, customerID)
	if err != nil {
		return err
	}

	if customer == nil {
		return fmt.Errorf("customer not found: %s", customerID)
	}

	// Partition [customer]:[year] is used to get yearly rollups.
	err = t.backfillYearlyRollup(logger, customer, "", "", dryRun)
	if err != nil {
		return err
	}

	// Partition [customer]:[product]:[year] is used to get yearly rollups.
	err = t.backfillYearlyRollup(logger, customer, "copilot", "", dryRun)
	if err != nil {
		return err
	}

	// Partition [customer]:[sku]:[year] is used to get yearly rollups.
	err = t.backfillYearlyRollup(logger, customer, "", "copilot_for_business", dryRun)
	if err != nil {
		return err
	}

	// Partition [customer]:[sku]:[year] is used to get yearly rollups.
	err = t.backfillYearlyRollup(logger, customer, "", "copilot_enterprise", dryRun)
	if err != nil {
		return err
	}

	// Partition [customer]:[sku]:[year] is used to get yearly rollups.
	err = t.backfillYearlyRollup(logger, customer, "", "copilot_standalone", dryRun)
	if err != nil {
		return err
	}

	// TODO: Replace all occurrences of 'bpErr' with 'err' to handle errors throughout the code.
	// we will replace the standard error package with the bperrors package and use
	// the err variable to handle errors throughout the code.
	costCenters, bpErr := t.costCenterEngine.GetAllCostCenters(t.ctx, logger, customer)
	if bpErr != nil {
		logger.WithError(bpErr.OriginalError).Error(bpErr.FriendlyError.Error())
		return bpErr
	}

	for _, costCenter := range costCenters {
		logger.Info("Running BackfillYearlyRollups transition on cost center...", kvp.String(logging.BillingPlatformCostCenterUUID, costCenter.CostCenterKey.UUID))

		costCenterCustomer, err := t.customerEngine.Get(t.ctx, logger, costCenter.CostCenterKey.UUID)
		if err != nil {
			logger.WithError(err).Error("failed to get cost center customer")
			continue
		}

		if costCenterCustomer == nil {
			logger.Info("Cost center customer not found")
			continue
		}

		// Partition [costCenterUUID]:[year] is used to get yearly rollups.
		err = t.backfillYearlyRollup(logger, costCenterCustomer, "", "", dryRun)
		if err != nil {
			return err
		}

		// Partition [costCenterUUID]:[product]:[year] is used to get yearly rollups.
		err = t.backfillYearlyRollup(logger, costCenterCustomer, "copilot", "", dryRun)
		if err != nil {
			return err
		}

		// Partition [costCenterUUID]:[sku]:[year] is used to get yearly rollups.
		err = t.backfillYearlyRollup(logger, costCenterCustomer, "", "copilot_for_business", dryRun)
		if err != nil {
			return err
		}

		// Partition [costCenterUUID]:[sku]:[year] is used to get yearly rollups.
		err = t.backfillYearlyRollup(logger, costCenterCustomer, "", "copilot_enterprise", dryRun)
		if err != nil {
			return err
		}

		// Partition [costCenterUUID]:[sku]:[year] is used to get yearly rollups.
		err = t.backfillYearlyRollup(logger, costCenterCustomer, "", "copilot_standalone", dryRun)
		if err != nil {
			return err
		}
	}

	return nil
}

func (t *BackfillYearlyRollups) backfillYearlyRollup(logger log.Logger, customer *models.Customer, product string, sku string, dryRun bool) error {
	// Backfilling only 2024.
	year := int64(2024)

	// Attempt to get yearly rollups for the desired year.
	//
	// Example partitionKeys for yearly rollups:
	//   1:copilot:2024 => Copilot usage (all SKUs) for 2024.
	//   1:copilot_standalone:2024 => Copilot Standalone usage for 2024.
	yearlyPartitionDetail := &models.UsagePartitionDetail{
		UsageEntityId: customer.GetCustomerId(),
		UsageTime:     models.NewUsageTime().WithYear(year),
		Product:       product,
		Sku:           sku,
		ActiveType:    models.Yearly,
	}

	yearlyUsageLineItems, err := t.usageEngine.GetLineItems(t.ctx, logger, yearlyPartitionDetail)
	if err != nil {
		return err
	}

	// For each yearly rollup found, attempt to get monthly SKU rollups.
	// Partition keys are constructed based on the yearly document ID.
	//
	// Example yearly rollup document ID:
	//   1:copilot_standalone:2024:5
	//
	// Resulting monthly SKU rollup partition key is the same:
	//   1:copilot_standalone:2024:5
	//
	// NOTE: a product monthly rollup is also available (1:copilot:2024:5), but it contains the same
	// data as the SKU monthly rollup. When a product is specified, all SKU monthly
	// rollups are considered and they update the specific SKU record on
	// the yearly product rollup.
	lineItemRateLimit := ratelimit.New(100) // 100 line items per second
	prev := time.Now()
	for _, yearlyUsageLineItem := range yearlyUsageLineItems {
		now := lineItemRateLimit.Take()

		if yearlyUsageLineItem.Pricing.Product != "copilot" {
			continue
		}

		yearlyBilledAmount := int64(0)
		yearlyQuantity := int64(0)
		yearlyFractionalQuantity := int64(0)
		yearlyFullQuantity := int64(0)

		logger.Info("Running transition on yearly line item",
			kvp.String("db.cosmosdb.partition_key", yearlyUsageLineItem.Key.PartitionKey),
			kvp.String("db.cosmosdb.id", yearlyUsageLineItem.Id),
		)

		month, err := strconv.Atoi(strings.Split(yearlyUsageLineItem.Id, ":")[3])
		if err != nil {
			return errors.Wrap(err, "failed to parse month")
		}

		monthlyPartitionDetail := &models.UsagePartitionDetail{
			UsageEntityId: customer.GetCustomerId(),
			UsageTime:     models.NewUsageTime().WithYear(year).WithMonth(time.Month(month)),
			Sku:           yearlyUsageLineItem.Pricing.Sku,
			ActiveType:    models.Monthly,
		}

		logger.Info("Getting monthly partition", kvp.String("db.cosmosdb.partition_key", monthlyPartitionDetail.ToPartitionKey()))

		monthlyUsageLineItems, err := t.usageEngine.GetLineItems(t.ctx, logger, monthlyPartitionDetail)
		if err != nil {
			return err
		}

		for _, monthlyUsageLineItem := range monthlyUsageLineItems {
			logger.Info("Aggregating monthly line item",
				kvp.String("db.cosmosdb.partition_key", monthlyUsageLineItem.Key.PartitionKey),
				kvp.String("db.cosmosdb.id", monthlyUsageLineItem.Id),
			)
			yearlyBilledAmount += monthlyUsageLineItem.BilledAmount
			yearlyQuantity += monthlyUsageLineItem.Quantity
			yearlyFractionalQuantity += monthlyUsageLineItem.FractionalQuantity
			yearlyFullQuantity += monthlyUsageLineItem.FullQuantity
		}

		logger.Info("Yearly rollup before result",
			kvp.String("db.cosmosdb.partition_key", yearlyPartitionDetail.ToPartitionKey()),
			kvp.String("db.cosmosdb.id", yearlyUsageLineItem.Id),
			kvp.Int64("gh.billing_platform.transition.yearly_billed_amount", yearlyUsageLineItem.BilledAmount),
			kvp.Int64("gh.billing_platform.transition.yearly_quantity", yearlyUsageLineItem.Quantity),
			kvp.Int64("gh.billing_platform.transition.yearly_fractional_quantity", yearlyUsageLineItem.FractionalQuantity),
			kvp.Int64("gh.billing_platform.transition.yearly_full_quantity", yearlyUsageLineItem.FullQuantity),
		)
		logger.Info("Yearly rollup after result",
			kvp.String("db.cosmosdb.partition_key", yearlyPartitionDetail.ToPartitionKey()),
			kvp.String("db.cosmosdb.id", yearlyUsageLineItem.Id),
			kvp.Int64("gh.billing_platform.transition.yearly_billed_amount", yearlyBilledAmount),
			kvp.Int64("gh.billing_platform.transition.yearly_quantity", yearlyQuantity),
			kvp.Int64("gh.billing_platform.transition.yearly_fractional_quantity", yearlyFractionalQuantity),
			kvp.Int64("gh.billing_platform.transition.yearly_full_quantity", yearlyFullQuantity),
		)

		if !dryRun {
			po := azcosmos.PatchOperations{}
			po.AppendAdd("/BilledAmount", yearlyBilledAmount)
			po.AppendAdd("/Quantity", yearlyQuantity)
			po.AppendAdd("/FractionalQuantity", yearlyFractionalQuantity)
			po.AppendAdd("/FullQuantity", yearlyFullQuantity)
			err := t.db.PatchWithOptions(t.ctx, logger, yearlyUsageLineItem, po, nil)
			if err != nil {
				logger.WithError(err).Error("Failed to update yearly rollup")
				return err
			}
			logger.Info("Successfully updated yearly rollup", kvp.String("db.cosmosdb.partition_key", yearlyPartitionDetail.ToPartitionKey()))
		}

		logger.Info(fmt.Sprintf("Duration: %s", now.Sub(prev)))
		prev = now
	}

	return nil
}
