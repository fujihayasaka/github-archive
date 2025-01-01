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
var backfillMonthlyRollupsCustomerIDsFileData []byte

type BackfillMonthlyRollups struct {
	ctx              context.Context
	cfg              *config.Config
	logger           log.Logger
	costCenterEngine engines.CostCenterEngineInterface
	customerEngine   engines.CustomerEngineInterface
	usageEngine      engines.UsageEngineInterface
	db               interfaces.Database
}

func NewBackfillMonthlyRollups(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	costCenterEngine engines.CostCenterEngineInterface,
	customerEngine engines.CustomerEngineInterface,
	usageEngine engines.UsageEngineInterface,
	db interfaces.Database,
) *BackfillMonthlyRollups {
	return &BackfillMonthlyRollups{
		ctx:              ctx,
		cfg:              cfg,
		logger:           logger,
		costCenterEngine: costCenterEngine,
		customerEngine:   customerEngine,
		usageEngine:      usageEngine,
		db:               db,
	}
}

func (t *BackfillMonthlyRollups) Run(dryRun bool, customerIDList []string, useFile bool) error {
	t.logger.Info("Started BackfillMonthlyRollups transition ...")
	var customerIDs []string
	if useFile {
		t.logger.Info("Using file to get customerIDs",
			kvp.String("gh.billing_platform.transition.file_name", "inputs/backfillRollupsCustomerIds.csv"),
			kvp.Int("gh.billing_platform.transition.file_size_in_bytes", len(backfillMonthlyRollupsCustomerIDsFileData)),
		)
		backfillMonthlyRollupsCustomerIDs := strings.TrimSuffix(string(backfillMonthlyRollupsCustomerIDsFileData), "\n")
		customerIDs = strings.Split(backfillMonthlyRollupsCustomerIDs, ",")
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
		logger.Info("Successfully completed BackfillMonthlyRollups transition for customer")
		logger.Info(fmt.Sprintf("Duration: %s", now.Sub(prev)))
		prev = now
	}

	return nil
}

func (t *BackfillMonthlyRollups) RunTransitionForCustomer(dryRun bool, customerID string) error {
	logger := t.logger.WithFields(kvp.String(logging.BillingCustomerId, customerID))
	logger.Info("Running BackfillMonthlyRollups transition...")

	customer, err := t.customerEngine.Get(t.ctx, logger, customerID, false)
	if err != nil {
		return err
	}

	if customer == nil {
		return fmt.Errorf("customer not found: %s", customerID)
	}

	// Partition [customer]:[year]:[month] is used to get monthly rollups.
	err = t.backfillMonthlyRollup(logger, customer, "", "", dryRun)
	if err != nil {
		return err
	}

	// Partition [customer]:[product]:[year]:[month] is used to get monthly rollups.
	err = t.backfillMonthlyRollup(logger, customer, "copilot", "", dryRun)
	if err != nil {
		return err
	}

	// Partition [customer]:[sku]:[year]:[month] is used to get monthly rollups.
	err = t.backfillMonthlyRollup(logger, customer, "", "copilot_for_business", dryRun)
	if err != nil {
		return err
	}

	// Partition [customer]:[sku]:[year]:[month] is used to get monthly rollups.
	err = t.backfillMonthlyRollup(logger, customer, "", "copilot_enterprise", dryRun)
	if err != nil {
		return err
	}

	// Partition [customer]:[sku]:[year]:[month] is used to get monthly rollups.
	err = t.backfillMonthlyRollup(logger, customer, "", "copilot_standalone", dryRun)
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
		logger.Info("Running BackfillMonthlyRollups transition on cost center...", kvp.String(logging.BillingPlatformCostCenterUUID, costCenter.CostCenterKey.UUID))

		costCenterCustomer, err := t.customerEngine.Get(t.ctx, logger, costCenter.CostCenterKey.UUID, false)
		if err != nil {
			logger.WithError(err).Error("failed to get cost center customer")
			continue
		}

		if costCenterCustomer == nil {
			logger.Info("Cost center customer not found")
			continue
		}

		// Partition [costCenterUUID]:[year]:[month] is used to get monthly rollups.
		err = t.backfillMonthlyRollup(logger, costCenterCustomer, "", "", dryRun)
		if err != nil {
			return err
		}

		// Partition [costCenterUUID]:[product]:[year]:[month] is used to get monthly rollups.
		err = t.backfillMonthlyRollup(logger, costCenterCustomer, "copilot", "", dryRun)
		if err != nil {
			return err
		}

		// Partition [costCenterUUID]:[sku]:[year]:[month] is used to get monthly rollups.
		err = t.backfillMonthlyRollup(logger, costCenterCustomer, "", "copilot_for_business", dryRun)
		if err != nil {
			return err
		}

		// Partition [costCenterUUID]:[sku]:[year]:[month] is used to get monthly rollups.
		err = t.backfillMonthlyRollup(logger, costCenterCustomer, "", "copilot_enterprise", dryRun)
		if err != nil {
			return err
		}

		// Partition [costCenterUUID]:[sku]:[year]:[month] is used to get monthly rollups.
		err = t.backfillMonthlyRollup(logger, costCenterCustomer, "", "copilot_standalone", dryRun)
		if err != nil {
			return err
		}
	}

	return nil
}

func (t *BackfillMonthlyRollups) backfillMonthlyRollup(logger log.Logger, customer *models.Customer, product string, sku string, dryRun bool) error {
	// Backfilling only 2024.
	year := int64(2024)

	// For each month in the year, attempt to get monthly rollups.
	//
	// Example partitionKeys for monthly rollups:
	//   1:copilot:2024:5 => Copilot usage (all SKUs) for May, 2024.
	//   1:copilot_standalone:2024:5 => Copilot Standalone usage for May, 2024.
	for month := 1; month <= 12; month++ {
		monthlyPartitionDetail := &models.UsagePartitionDetail{
			UsageEntityId: customer.GetCustomerId(),
			UsageTime:     models.NewUsageTime().WithYear(year).WithMonth(time.Month(month)),
			Product:       product,
			Sku:           sku,
			ActiveType:    models.Monthly,
		}

		monthlyUsageLineItems, err := t.usageEngine.GetLineItems(t.ctx, logger, monthlyPartitionDetail)
		if err != nil {
			return err
		}

		// For each monthly rollup found, attempt to get daily SKU rollups.
		// Partition keys are constructed based on the monthly document ID.
		//
		// Example monthly rollup document ID:
		//   1:copilot_standalone:2024:5:25
		//
		// Resulting daily SKU rollup partition key is the same:
		//   1:copilot_standalone:2024:5:25
		//
		// NOTE: a product daily rollup is also available (1:copilot:2024:5:25), but it contains the same
		// data as the SKU daily rollup. When a product is specified, all SKU daily
		// rollups are considered and they update the specific SKU record on
		// the monthly product rollup.
		lineItemRateLimit := ratelimit.New(100) // 100 line items per second
		prev := time.Now()
		for _, monthlyUsageLineItem := range monthlyUsageLineItems {
			now := lineItemRateLimit.Take()

			if monthlyUsageLineItem.Pricing.Product != "copilot" {
				continue
			}

			monthlyBilledAmount := int64(0)
			monthlyQuantity := int64(0)
			monthlyFractionalQuantity := int64(0)
			monthlyFullQuantity := int64(0)

			logger.Info("Running transition on monthly line item",
				kvp.String("db.cosmosdb.partition_key", monthlyUsageLineItem.Key.PartitionKey),
				kvp.String("db.cosmosdb.id", monthlyUsageLineItem.Id),
			)

			day, err := strconv.Atoi(strings.Split(monthlyUsageLineItem.Id, ":")[4])
			if err != nil {
				return errors.Wrap(err, "failed to parse day")
			}

			dailyPartitionDetail := &models.UsagePartitionDetail{
				UsageEntityId: customer.GetCustomerId(),
				UsageTime:     models.NewUsageTime().WithYear(year).WithMonth(time.Month(month)).WithDay(day),
				Sku:           monthlyUsageLineItem.Pricing.Sku,
				ActiveType:    models.Daily,
			}

			logger.Info("Getting daily partition", kvp.String("db.cosmosdb.partition_key", dailyPartitionDetail.ToPartitionKey()))

			dailyUsageLineItems, err := t.usageEngine.GetLineItems(t.ctx, logger, dailyPartitionDetail)
			if err != nil {
				return err
			}

			for _, dailyUsageLineItem := range dailyUsageLineItems {
				logger.Info("Aggregating daily line item",
					kvp.String("db.cosmosdb.partition_key", dailyUsageLineItem.Key.PartitionKey),
					kvp.String("db.cosmosdb.id", dailyUsageLineItem.Id),
				)
				monthlyBilledAmount += dailyUsageLineItem.BilledAmount
				monthlyQuantity += dailyUsageLineItem.Quantity
				monthlyFractionalQuantity += dailyUsageLineItem.FractionalQuantity
				monthlyFullQuantity += dailyUsageLineItem.FullQuantity
			}

			logger.Info("Monthly rollup before result",
				kvp.String("db.cosmosdb.partition_key", monthlyPartitionDetail.ToPartitionKey()),
				kvp.String("db.cosmosdb.id", monthlyUsageLineItem.Id),
				kvp.Int64("gh.billing_platform.transition.monthly_billed_amount", monthlyUsageLineItem.BilledAmount),
				kvp.Int64("gh.billing_platform.transition.monthly_quantity", monthlyUsageLineItem.Quantity),
				kvp.Int64("gh.billing_platform.transition.monthly_fractional_quantity", monthlyUsageLineItem.FractionalQuantity),
				kvp.Int64("gh.billing_platform.transition.monthly_full_quantity", monthlyUsageLineItem.FullQuantity),
			)
			logger.Info("Monthly rollup after result",
				kvp.String("db.cosmosdb.partition_key", monthlyPartitionDetail.ToPartitionKey()),
				kvp.String("db.cosmosdb.id", monthlyUsageLineItem.Id),
				kvp.Int64("gh.billing_platform.transition.monthly_billed_amount", monthlyBilledAmount),
				kvp.Int64("gh.billing_platform.transition.monthly_quantity", monthlyQuantity),
				kvp.Int64("gh.billing_platform.transition.monthly_fractional_quantity", monthlyFractionalQuantity),
				kvp.Int64("gh.billing_platform.transition.monthly_full_quantity", monthlyFullQuantity),
			)

			if !dryRun {
				po := azcosmos.PatchOperations{}
				po.AppendAdd("/BilledAmount", monthlyBilledAmount)
				po.AppendAdd("/Quantity", monthlyQuantity)
				po.AppendAdd("/FractionalQuantity", monthlyFractionalQuantity)
				po.AppendAdd("/FullQuantity", monthlyFullQuantity)
				err := t.db.PatchWithOptions(t.ctx, logger, monthlyUsageLineItem, po, nil)
				if err != nil {
					logger.WithError(err).Error("Failed to update monthly rollup")
					return err
				}
				logger.Info("Successfully updated monthly rollup", kvp.String("db.cosmosdb.partition_key", monthlyPartitionDetail.ToPartitionKey()))
			}

			logger.Info(fmt.Sprintf("Duration: %s", now.Sub(prev)))
			prev = now
		}
	}

	return nil
}
