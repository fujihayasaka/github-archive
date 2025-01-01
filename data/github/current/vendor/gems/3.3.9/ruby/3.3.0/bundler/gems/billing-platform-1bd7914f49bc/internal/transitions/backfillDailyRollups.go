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
var backfillDailyRollupsCustomerIDsFileData []byte

type BackfillDailyRollups struct {
	ctx              context.Context
	cfg              *config.Config
	logger           log.Logger
	costCenterEngine engines.CostCenterEngineInterface
	customerEngine   *engines.CustomerEngine
	usageEngine      *engines.UsageEngine
	db               interfaces.Database
}

func NewBackfillDailyRollups(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	costCenterEngine engines.CostCenterEngineInterface,
	customerEngine *engines.CustomerEngine,
	usageEngine *engines.UsageEngine,
	db interfaces.Database,
) *BackfillDailyRollups {
	return &BackfillDailyRollups{
		ctx:              ctx,
		cfg:              cfg,
		logger:           logger,
		costCenterEngine: costCenterEngine,
		customerEngine:   customerEngine,
		usageEngine:      usageEngine,
		db:               db,
	}
}

func (t *BackfillDailyRollups) Run(dryRun bool, customerIDList []string, useFile bool) error {
	t.logger.Info("Started BackfillDailyRollups transition ...")
	var customerIDs []string
	if useFile {
		t.logger.Info("Using file to get customerIDs",
			kvp.String("gh.billing_platform.transition.file_name", "inputs/backfillRollupsCustomerIds.csv"),
			kvp.Int("gh.billing_platform.transition.file_size_in_bytes", len(backfillDailyRollupsCustomerIDsFileData)),
		)
		backfillDailyRollupsCustomerIDs := strings.TrimSuffix(string(backfillDailyRollupsCustomerIDsFileData), "\n")
		customerIDs = strings.Split(backfillDailyRollupsCustomerIDs, ",")
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
		logger.Info("Successfully completed BackfillDailyRollups transition for customer")
		logger.Info(fmt.Sprintf("Duration: %s", now.Sub(prev)))
		prev = now
	}

	return nil
}

func (t *BackfillDailyRollups) RunTransitionForCustomer(dryRun bool, customerID string) error {
	logger := t.logger.WithFields(kvp.String(logging.BillingCustomerId, customerID))
	logger.Info("Running BackfillDailyRollups transition...")

	customer, err := t.customerEngine.Get(t.ctx, logger, customerID)
	if err != nil {
		return err
	}

	if customer == nil {
		return fmt.Errorf("customer not found: %s", customerID)
	}

	// Partition [customer]:[year]:[month]:[day] is used to get daily rollups.
	err = t.backfillDailyRollup(logger, customer, "", "", dryRun)
	if err != nil {
		return err
	}

	// Partition [customer]:[product]:[year]:[month]:[day] is used to get daily rollups.
	err = t.backfillDailyRollup(logger, customer, "copilot", "", dryRun)
	if err != nil {
		return err
	}

	// Partition [customer]:[sku]:[year]:[month]:[day] is used to get daily rollups.
	err = t.backfillDailyRollup(logger, customer, "", "copilot_for_business", dryRun)
	if err != nil {
		return err
	}

	// Partition [customer]:[sku]:[year]:[month]:[day] is used to get daily rollups.
	err = t.backfillDailyRollup(logger, customer, "", "copilot_enterprise", dryRun)
	if err != nil {
		return err
	}

	// Partition [customer]:[sku]:[year]:[month]:[day] is used to get daily rollups.
	err = t.backfillDailyRollup(logger, customer, "", "copilot_standalone", dryRun)
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
		logger.Info("Running BackfillDailyRollups transition on cost center...", kvp.String(logging.BillingPlatformCostCenterUUID, costCenter.CostCenterKey.UUID))

		costCenterCustomer, err := t.customerEngine.Get(t.ctx, logger, costCenter.CostCenterKey.UUID)
		if err != nil {
			logger.WithError(err).Error("failed to get cost center customer")
			continue
		}

		if costCenterCustomer == nil {
			logger.Info("Cost center customer not found")
			continue
		}

		// Partition [costCenterUUID]:[year]:[month]:[day] is used to get daily rollups.
		err = t.backfillDailyRollup(logger, costCenterCustomer, "", "", dryRun)
		if err != nil {
			return err
		}

		// Partition [costCenterUUID]:[product]:[year]:[month]:[day] is used to get daily rollups.
		err = t.backfillDailyRollup(logger, costCenterCustomer, "copilot", "", dryRun)
		if err != nil {
			return err
		}

		// Partition [costCenterUUID]:[sku]:[year]:[month]:[day] is used to get daily rollups.
		err = t.backfillDailyRollup(logger, costCenterCustomer, "", "copilot_for_business", dryRun)
		if err != nil {
			return err
		}

		// Partition [costCenterUUID]:[sku]:[year]:[month]:[day] is used to get daily rollups.
		err = t.backfillDailyRollup(logger, costCenterCustomer, "", "copilot_enterprise", dryRun)
		if err != nil {
			return err
		}

		// Partition [costCenterUUID]:[sku]:[year]:[month]:[day] is used to get daily rollups.
		err = t.backfillDailyRollup(logger, costCenterCustomer, "", "copilot_standalone", dryRun)
		if err != nil {
			return err
		}
	}

	return nil
}

func (t *BackfillDailyRollups) backfillDailyRollup(logger log.Logger, customer *models.Customer, product string, sku string, dryRun bool) error {
	// Backfilling only May, 2024.
	year := int64(2024)
	month := int64(5)

	// For each day in the month, attempt to get daily rollups.
	//
	// Example partitionKeys for daily rollups:
	//   1:copilot:2024:5:25 => Copilot usage (all SKUs) for May 25, 2024.
	//   1:copilot_standalone:2024:5:25 => Copilot Standalone usage for May 25, 2024.
	for day := 1; day <= 31; day++ {
		dailyPartitionDetail := &models.UsagePartitionDetail{
			UsageEntityId: customer.GetCustomerId(),
			UsageTime:     models.NewUsageTime().WithYear(year).WithMonth(time.Month(month)).WithDay(day),
			Product:       product,
			Sku:           sku,
			ActiveType:    models.Daily,
		}

		dailyUsageLineItems, err := t.usageEngine.GetLineItems(t.ctx, logger, dailyPartitionDetail)
		if err != nil {
			return err
		}

		// For each daily rollup found, attempt to get hourly SKU rollups.
		// Partition keys are constructed based on the daily document ID.
		//
		// Example daily rollup document ID:
		//   1:copilot_standalone:2024:5:25:1
		//
		// Resulting hourly SKU rollup partition key is the same:
		//   1:copilot_standalone:2024:5:25:1
		//
		// NOTE: a product hourly rollup is also available (1:copilot:2024:5:25:1), but it contains the same
		// data as the SKU hourly rollup. When a product is specified, all SKU hourly
		// rollups are considered and they update the specific SKU record on
		// the daily product rollup.
		lineItemRateLimit := ratelimit.New(100) // 100 line items per second
		prev := time.Now()
		for _, dailyUsageLineItem := range dailyUsageLineItems {
			now := lineItemRateLimit.Take()

			if dailyUsageLineItem.Pricing.Product != "copilot" {
				continue
			}

			dailyBilledAmount := int64(0)
			dailyQuantity := int64(0)
			dailyFractionalQuantity := int64(0)
			dailyFullQuantity := int64(0)

			logger.Info("Running transition on daily line item",
				kvp.String("db.cosmosdb.partition_key", dailyUsageLineItem.Key.PartitionKey),
				kvp.String("db.cosmosdb.id", dailyUsageLineItem.Id),
			)

			day, err := strconv.Atoi(strings.Split(dailyUsageLineItem.Id, ":")[4])
			if err != nil {
				return errors.Wrap(err, "failed to parse day")
			}

			hour, err := strconv.Atoi(strings.Split(dailyUsageLineItem.Id, ":")[5])
			if err != nil {
				return errors.Wrap(err, "failed to parse hour")
			}

			hourlyPartitionDetail := &models.UsagePartitionDetail{
				UsageEntityId: customer.GetCustomerId(),
				UsageTime:     models.NewUsageTime().WithYear(year).WithMonth(time.Month(month)).WithDay(day).WithHour(hour),
				Sku:           dailyUsageLineItem.Pricing.Sku,
				ActiveType:    models.Hourly,
			}

			logger.Info("Getting hourly partition", kvp.String("db.cosmosdb.partition_key", hourlyPartitionDetail.ToPartitionKey()))

			hourlyUsageLineItems, err := t.usageEngine.GetLineItems(t.ctx, logger, hourlyPartitionDetail)
			if err != nil {
				return err
			}

			for _, hourlyUsageLineItem := range hourlyUsageLineItems {
				logger.Info("Aggregating hourly line item",
					kvp.String("db.cosmosdb.partition_key", hourlyUsageLineItem.Key.PartitionKey),
					kvp.String("db.cosmosdb.id", hourlyUsageLineItem.Id),
				)
				if hourlyUsageLineItem.Quantity < 0 {
					logger.Info("Skipping hourly line item with negative quantity", kvp.String("db.cosmosdb.partition_key", hourlyPartitionDetail.ToPartitionKey()))
					continue
				}
				dailyBilledAmount += hourlyUsageLineItem.BilledAmount
				dailyQuantity += hourlyUsageLineItem.Quantity
				dailyFractionalQuantity += hourlyUsageLineItem.FractionalQuantity
				dailyFullQuantity += hourlyUsageLineItem.FullQuantity
			}

			logger.Info("Daily rollup before result",
				kvp.String("db.cosmosdb.partition_key", dailyPartitionDetail.ToPartitionKey()),
				kvp.String("db.cosmosdb.id", dailyUsageLineItem.Id),
				kvp.Int64("gh.billing_platform.transition.daily_billed_amount", dailyUsageLineItem.BilledAmount),
				kvp.Int64("gh.billing_platform.transition.daily_quantity", dailyUsageLineItem.Quantity),
				kvp.Int64("gh.billing_platform.transition.daily_fractional_quantity", dailyUsageLineItem.FractionalQuantity),
				kvp.Int64("gh.billing_platform.transition.daily_full_quantity", dailyUsageLineItem.FullQuantity),
			)
			logger.Info("Daily rollup after result",
				kvp.String("db.cosmosdb.partition_key", dailyPartitionDetail.ToPartitionKey()),
				kvp.String("db.cosmosdb.id", dailyUsageLineItem.Id),
				kvp.Int64("gh.billing_platform.transition.daily_billed_amount", dailyBilledAmount),
				kvp.Int64("gh.billing_platform.transition.daily_quantity", dailyQuantity),
				kvp.Int64("gh.billing_platform.transition.daily_fractional_quantity", dailyFractionalQuantity),
				kvp.Int64("gh.billing_platform.transition.daily_full_quantity", dailyFullQuantity),
			)

			if !dryRun {
				if dailyUsageLineItem.BilledAmount == dailyBilledAmount &&
					dailyUsageLineItem.Quantity == dailyQuantity &&
					dailyUsageLineItem.FractionalQuantity == dailyFractionalQuantity &&
					dailyUsageLineItem.FullQuantity == dailyFullQuantity {
					logger.Info("Skipping daily rollup update. All values are the same", kvp.String("db.cosmosdb.partition_key", dailyPartitionDetail.ToPartitionKey()))
				} else {
					po := azcosmos.PatchOperations{}
					po.AppendAdd("/BilledAmount", dailyBilledAmount)
					po.AppendAdd("/Quantity", dailyQuantity)
					po.AppendAdd("/FractionalQuantity", dailyFractionalQuantity)
					po.AppendAdd("/FullQuantity", dailyFullQuantity)
					err := t.db.PatchWithOptions(t.ctx, logger, dailyUsageLineItem, po, nil)
					if err != nil {
						logger.WithError(err).Error("Failed to update daily rollup")
						return err
					}
					logger.Info("Successfully updated daily rollup", kvp.String("db.cosmosdb.partition_key", dailyPartitionDetail.ToPartitionKey()))
				}
			}

			logger.Info(fmt.Sprintf("Duration: %s", now.Sub(prev)))
			prev = now
		}
	}

	return nil
}
