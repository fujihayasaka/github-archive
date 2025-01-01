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

//go:embed inputs/correctUsageCustomers.csv
var correctUsageCustomersFileData []byte

const (
	ByDefault           = "byDefault"
	ByProduct           = "byProduct"
	BySku               = "bySku"
	ByProductSku        = "byProductSku"
	ByOrgRepoProductSku = "byOrgRepoProductSku"
)

type CorrectUsageCustomer struct {
	CustomerID string
	OrgId      string
}

type CorrectUsageTransition struct {
	ctx              context.Context
	cfg              *config.Config
	logger           log.Logger
	costCenterEngine engines.CostCenterEngineInterface
	customerEngine   engines.CustomerEngineInterface
	usageEngine      engines.UsageEngineInterface
	db               interfaces.Database
}

func NewCorrectUsageTransition(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	costCenterEngine engines.CostCenterEngineInterface,
	customerEngine engines.CustomerEngineInterface,
	usageEngine engines.UsageEngineInterface,
	db interfaces.Database,
) *CorrectUsageTransition {
	return &CorrectUsageTransition{
		ctx:              ctx,
		cfg:              cfg,
		logger:           logger,
		costCenterEngine: costCenterEngine,
		customerEngine:   customerEngine,
		usageEngine:      usageEngine,
		db:               db,
	}
}

// This transition is designed for:
// - Standalone organizations
// - Removing all usage for a particular product and sku for a set of customers in a month and year and day range
// - A CSV that has both the customerId and orgId
// - Removing usage for seat-based products
//
// It is not designed for:
// - Enterprises
// - Removing usage associated with cost centers
// - Removing any usage emitted to Zuora or Azure
// - Removing any usage in the data warehouse (submit a data request here to do that: https://github.com/github/data/issues/new?template=data-request-.md)
// - Being specific about removing usage on particular days but keeping others (the year and month corrections would need to be updated for this)
// - Usage assigned to repos (would need to expand the `byProductSku` logic to accommodate products assigned at the repo level)
func (t *CorrectUsageTransition) Run(dryRun bool, sku string, product string, startDate string, endDate string) error {
	t.logger.Info("Started CorrectUsageTransition transition ...")
	t.logger.Info("Using file to get customers",
		kvp.String("gh.billing_platform.transition.file_name", "inputs/correctUsageCustomerIds.csv"),
		kvp.Int("gh.billing_platform.transition.file_size_in_bytes", len(correctUsageCustomersFileData)),
	)
	correctUsageCustomerIDs := strings.TrimSuffix(string(correctUsageCustomersFileData), "\n")
	correctUsageCustomers := strings.Split(correctUsageCustomerIDs, "\n")
	t.logger.Info(fmt.Sprintf("%d customer(s) found", len(correctUsageCustomers)))
	customers := []CorrectUsageCustomer{}
	for _, correctUsageCustomer := range correctUsageCustomers {
		rawCustomer := strings.Split(correctUsageCustomer, ",")
		if len(rawCustomer) != 2 {
			t.logger.Error("Invalid customer format")
			continue
		}

		customer := CorrectUsageCustomer{
			CustomerID: rawCustomer[0],
			OrgId:      rawCustomer[1],
		}

		customers = append(customers, customer)
	}

	t.logger.Info(fmt.Sprintf("%d customer(s) found", len(customers)))

	customerRateLimit := ratelimit.New(1) // 1 customer per second
	prev := time.Now()
	for _, customer := range customers {
		now := customerRateLimit.Take()
		logger := t.logger.WithFields(kvp.String(logging.BillingCustomerId, customer.CustomerID))
		err := t.RunTransitionForCustomer(dryRun, customer, product, sku, startDate, endDate)
		if err != nil {
			logger.WithError(err).Error("Failed to run transition for customer")
			continue
		}
		logger.Info("Successfully completed CorrectUsageTransition for customer")
		logger.Info(fmt.Sprintf("Duration: %s", now.Sub(prev)))
		prev = now
	}

	return nil
}

func (t *CorrectUsageTransition) RunTransitionForCustomer(dryRun bool, customer CorrectUsageCustomer, product string, sku string, startDate string, endDate string) error {
	customerID := customer.CustomerID
	logger := t.logger.WithFields(kvp.String(logging.BillingCustomerId, customerID))
	logger.Info("Running CorrectUsageTransition transition...")

	orgId, err := strconv.ParseInt(customer.OrgId, 10, 64)
	if err != nil {
		return fmt.Errorf("failed to parse orgId: %s", customerID)
	}

	currentCustomer, err := t.customerEngine.Get(t.ctx, logger, customerID, false)
	if err != nil {
		return err
	}

	if currentCustomer == nil {
		return fmt.Errorf("customer not found: %s", customerID)
	}

	err = t.correctUsage(logger, currentCustomer, product, sku, startDate, endDate, orgId, dryRun)
	if err != nil {
		return err
	}

	return nil
}

func (t *CorrectUsageTransition) correctUsage(logger log.Logger, customer *models.Customer, product string, sku string, startDate string, endDate string, orgId int64, dryRun bool) error {
	// Parse time between startDate and endDate
	startTime, err := time.Parse("2006-01-02", startDate)
	if err != nil {
		return errors.Wrap(err, "failed to parse start date")
	}

	endTime, err := time.Parse("2006-01-02", endDate)
	if err != nil {
		return errors.Wrap(err, "failed to parse end date")
	}

	// For now we are going to assume that all passed in startTimes and endTimes
	// will be within the same month. This could be expanded in the future to
	// support other times.

	year := int64(startTime.Year())
	month := int64(startTime.Month())
	firstDay := startTime.Day()
	lastDay := endTime.Day()

	logger.Info("Correcting usage for date: ", kvp.Int64("gh.billing_platform.transition.year", year), kvp.Int64("gh.billing_platform.transition.month", month), kvp.Int("gh.billing_platform.transition.first_day", firstDay), kvp.Int("gh.billing_platform.transition.last_day", lastDay))

	// Loop through each day in the month and correct the daily rollups
	for day := firstDay; day <= lastDay; day++ {
		err = t.correctDailyUsage(logger, customer, product, sku, year, month, day, orgId, dryRun, ByDefault)
		if err != nil {
			return errors.Wrap(err, "failed to correct daily usage")
		}

		err = t.correctDailyUsage(logger, customer, product, sku, year, month, day, orgId, dryRun, ByProduct)
		if err != nil {
			return errors.Wrap(err, "failed to correct daily product usage")
		}

		err = t.correctDailyUsage(logger, customer, product, sku, year, month, day, orgId, dryRun, BySku)
		if err != nil {
			return errors.Wrap(err, "failed to correct daily sku usage")
		}

		err = t.correctDailyUsage(logger, customer, product, sku, year, month, day, orgId, dryRun, ByProductSku)
		if err != nil {
			return errors.Wrap(err, "failed to correct daily usage byProductSku")
		}

		err = t.correctDailyUsage(logger, customer, product, sku, year, month, day, orgId, dryRun, ByOrgRepoProductSku)
		if err != nil {
			return errors.Wrap(err, "failed to correct daily usage byOrgRepoProductSku")
		}
	}

	// Correct the month rollups
	err = t.correctMonthlyUsage(logger, customer, product, sku, year, month, orgId, dryRun, ByDefault)
	if err != nil {
		return errors.Wrap(err, "failed to correct monthly usage")
	}

	// Correct the month rollups for product
	err = t.correctMonthlyUsage(logger, customer, product, sku, year, month, orgId, dryRun, ByProduct)
	if err != nil {
		return errors.Wrap(err, "failed to correct monthly product usage")
	}

	// Correct the month rollups for sku
	err = t.correctMonthlyUsage(logger, customer, product, sku, year, month, orgId, dryRun, BySku)
	if err != nil {
		return errors.Wrap(err, "failed to correct monthly product usage")
	}

	// Correct the month rollups byProductSku
	err = t.correctMonthlyUsage(logger, customer, product, sku, year, month, orgId, dryRun, ByProductSku)
	if err != nil {
		return errors.Wrap(err, "failed to correct monthly usage byProductSku")
	}

	// Correct the month rollups byOrgRepoProductSku
	err = t.correctMonthlyUsage(logger, customer, product, sku, year, month, orgId, dryRun, ByOrgRepoProductSku)
	if err != nil {
		return errors.Wrap(err, "failed to correct monthly usage byOrgRepoProductSku")
	}

	// Correct the year rollups
	err = t.correctYearlyUsage(logger, customer, product, sku, year, orgId, dryRun, ByDefault)
	if err != nil {
		return errors.Wrap(err, "failed to correct yearly usage")
	}

	// Correct the year rollups for product
	err = t.correctYearlyUsage(logger, customer, product, sku, year, orgId, dryRun, ByProduct)
	if err != nil {
		return errors.Wrap(err, "failed to correct yearly product usage")
	}

	// Correct the year rollups for sku
	err = t.correctYearlyUsage(logger, customer, product, sku, year, orgId, dryRun, BySku)
	if err != nil {
		return errors.Wrap(err, "failed to correct yearly sku usage")
	}

	// Correct the year rollups byProductSku
	err = t.correctYearlyUsage(logger, customer, product, sku, year, orgId, dryRun, ByProductSku)
	if err != nil {
		return errors.Wrap(err, "failed to correct yearly usage byProductSku")
	}

	// Correct the year rollups byOrgRepoProductSku
	err = t.correctYearlyUsage(logger, customer, product, sku, year, orgId, dryRun, ByOrgRepoProductSku)
	if err != nil {
		return errors.Wrap(err, "failed to correct yearly usage byOrgRepoProductSku")
	}

	return nil
}

func (t *CorrectUsageTransition) correctDailyUsage(logger log.Logger, customer *models.Customer, product string, sku string, year int64, month int64, day int, orgId int64, dryRun bool, runType string) error {
	// Get daily rollups for the day for product usage
	// Example documents for daily rollups:
	//   pk: 1:2024:5:25 => Usage (all SKUs) for May 25, 2024.
	//   id: 1:copilot_standalone:2024:5:25:20 => Copilot Standalone usage for May 25, 2024 at hour 20.
	//
	// Example documents for daily rollups for product:
	//   pk: 1:copilot:2024:5:25 => Copilot usage (all Copilot SKUs) for May 25, 2024.
	//   id: 1:copilot_standalone:2024:5:25:20 => Copilot Standalone usage for May 25, 2024 at hour 20.
	//
	// Example documents for daily rollups for sku:
	//   pk: 1:copilot_standalone:2024:5:25 => Copilot usage for copilot_standalone sku for May 25, 2024.
	//   id: 1:copilot_standalone:2024:5:25:20 => Copilot Standalone usage for May 25, 2024 at hour 20
	//
	// Example documents for daily rollups for byProductSku:
	//   pk: 1:org:2:2024:5:25:byProductSku => Usage (all SKUs) for org 2 for May 25, 2024.
	//   id: 1:copilot_standalone:2024:5:25:20 => Copilot Standalone usage for org 2 for May 25, 2024 at hour 20
	//
	// Example documents for daily rollups for byOrgRepoProductSku:
	//   pk: 1:2024:5:25:byOrgRepoProductSku => Usage (all SKUs) sku for May 25, 2024.
	//   id: customer:1:org:2:repo:3:product:copilot:sku:copilot_standalone:2024:5:25:20 => Copilot Standalone usage for org 2 repo 3 for May 25, 2024 at hour 20
	//

	logger.Info("Running transition on daily rollup")
	dailyPartitionDetail := &models.UsagePartitionDetail{
		UsageEntityId: customer.GetCustomerId(),
		UsageTime:     models.NewUsageTime().WithYear(year).WithMonth(time.Month(month)).WithDay(day),
		ActiveType:    models.Daily,
	}

	if runType == ByProduct {
		dailyPartitionDetail = &models.UsagePartitionDetail{
			UsageEntityId: customer.GetCustomerId(),
			UsageTime:     models.NewUsageTime().WithYear(year).WithMonth(time.Month(month)).WithDay(day),
			Product:       product,
			ActiveType:    models.Daily,
		}
	}

	if runType == BySku {
		dailyPartitionDetail = &models.UsagePartitionDetail{
			UsageEntityId: customer.GetCustomerId(),
			UsageTime:     models.NewUsageTime().WithYear(year).WithMonth(time.Month(month)).WithDay(day),
			Sku:           sku,
			ActiveType:    models.Daily,
		}
	}

	if runType == ByProductSku {
		dailyPartitionDetail = &models.UsagePartitionDetail{
			UsageEntityId: customer.GetCustomerId(),
			UsageTime:     models.NewUsageTime().WithYear(year).WithMonth(time.Month(month)).WithDay(day),
			ActiveType:    models.Daily,
			OrgId:         orgId,
			GroupBy:       models.ByProductSkuGrouping,
		}
	}

	if runType == ByOrgRepoProductSku {
		dailyPartitionDetail = &models.UsagePartitionDetail{
			UsageEntityId: customer.GetCustomerId(),
			UsageTime:     models.NewUsageTime().WithYear(year).WithMonth(time.Month(month)).WithDay(day),
			ActiveType:    models.Daily,
			GroupBy:       models.ByOrgRepoProductSkuGrouping,
		}
	}

	dailyUsageLineItems, err := t.usageEngine.GetLineItems(t.ctx, logger, dailyPartitionDetail)
	if err != nil {
		return err
	}

	logger.Info("Daily usage line items found", kvp.Int("gh.billing_platform.transition.line_items_found", len(dailyUsageLineItems)), kvp.String("db.cosmosdb.partition_key", dailyPartitionDetail.ToGetLineItemsPartitionKey()))

	lineItemRateLimit := ratelimit.New(100) // 100 line items per second
	prev := time.Now()
	for _, dailyUsageLineItem := range dailyUsageLineItems {
		now := lineItemRateLimit.Take()

		if dailyUsageLineItem.Pricing.Product != product {
			continue
		}

		if dailyUsageLineItem.Pricing.Sku != sku {
			continue
		}

		if runType == ByOrgRepoProductSku {
			if dailyUsageLineItem.EntityDetail.OrganizationId != orgId {
				continue
			}
		}

		dailyBilledAmount := int64(0)
		dailyQuantity := int64(0)
		dailyFractionalQuantity := int64(0)
		dailyFullQuantity := int64(0)

		logger.Info("Running transition on daily line item",
			kvp.String("db.cosmosdb.partition_key", dailyUsageLineItem.Key.PartitionKey),
			kvp.String("db.cosmosdb.id", dailyUsageLineItem.Id),
		)

		logger.Info("Daily rollup before result",
			kvp.String("db.cosmosdb.partition_key", dailyPartitionDetail.ToGetLineItemsPartitionKey()),
			kvp.String("db.cosmosdb.id", dailyUsageLineItem.Id),
			kvp.Int64("gh.billing_platform.transition.daily_billed_amount", dailyUsageLineItem.BilledAmount),
			kvp.Int64("gh.billing_platform.transition.daily_quantity", dailyUsageLineItem.Quantity),
			kvp.Int64("gh.billing_platform.transition.daily_fractional_quantity", dailyUsageLineItem.FractionalQuantity),
			kvp.Int64("gh.billing_platform.transition.daily_full_quantity", dailyUsageLineItem.FullQuantity),
		)
		logger.Info("Daily rollup after result",
			kvp.String("db.cosmosdb.partition_key", dailyPartitionDetail.ToGetLineItemsPartitionKey()),
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
				logger.Info("Skipping daily rollup update. All values are the same", kvp.String("db.cosmosdb.partition_key", dailyPartitionDetail.ToGetLineItemsPartitionKey()))
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
				logger.Info("Successfully updated daily rollup", kvp.String("db.cosmosdb.partition_key", dailyPartitionDetail.ToGetLineItemsPartitionKey()))
			}

			// If this is the byOrgRepoProductSku rollup, we also need to check hourly rollups
			// Example documents for daily rollups for byOrgRepoProductSku:
			//   pk: 1:2024:5:25:17:byOrgRepoProductSku => Usage (all SKUs) sku for May 25, 2024.
			//   id: uuid => uuid of usage
			//
			// customerID:year:month:day:hour:byOrgRepoProductSku
			if runType == ByOrgRepoProductSku {
				maxHour := 24
				for i := 0; i < maxHour; i++ {
					hourlyPartitionDetail := &models.UsagePartitionDetail{
						UsageEntityId: customer.GetCustomerId(),
						UsageTime:     models.NewUsageTime().WithYear(year).WithMonth(time.Month(month)).WithDay(day).WithHour(i),
						ActiveType:    models.Hourly,
						GroupBy:       models.ByOrgRepoProductSkuGrouping,
					}

					logger.Info("Getting hourly partition", kvp.String("db.cosmosdb.partition_key", hourlyPartitionDetail.ToGetLineItemsPartitionKey()))

					hourlyUsageLineItems, err := t.usageEngine.GetLineItems(t.ctx, logger, hourlyPartitionDetail)
					if err != nil {
						return err
					}

					for _, hourlyUsageLineItem := range hourlyUsageLineItems {
						if hourlyUsageLineItem.Pricing.Product != product {
							continue
						}

						if hourlyUsageLineItem.Pricing.Sku != sku {
							continue
						}

						if hourlyUsageLineItem.EntityDetail.OrganizationId != orgId {
							continue
						}

						if hourlyUsageLineItem.BilledAmount == dailyBilledAmount &&
							hourlyUsageLineItem.Quantity == dailyQuantity &&
							hourlyUsageLineItem.FractionalQuantity == dailyFractionalQuantity &&
							hourlyUsageLineItem.FullQuantity == dailyFullQuantity {
							logger.Info("Skipping hourly rollup update. All values are the same", kvp.String("db.cosmosdb.partition_key", hourlyPartitionDetail.ToGetLineItemsPartitionKey()))
						} else {
							po := azcosmos.PatchOperations{}
							po.AppendAdd("/BilledAmount", dailyBilledAmount)
							po.AppendAdd("/Quantity", dailyQuantity)
							po.AppendAdd("/FractionalQuantity", dailyFractionalQuantity)
							po.AppendAdd("/FullQuantity", dailyFullQuantity)
							err := t.db.PatchWithOptions(t.ctx, logger, hourlyUsageLineItem, po, nil)
							if err != nil {
								logger.WithError(err).Error("Failed to update daily rollup")
								return err
							}
							logger.Info("Successfully hourly daily rollup", kvp.String("db.cosmosdb.partition_key", hourlyPartitionDetail.ToGetLineItemsPartitionKey()))
						}
					}
				}
			}
		}

		logger.Info(fmt.Sprintf("Duration: %s", now.Sub(prev)))
		prev = now
	}

	return nil
}

func (t *CorrectUsageTransition) correctMonthlyUsage(logger log.Logger, customer *models.Customer, product string, sku string, year int64, month int64, orgId int64, dryRun bool, runType string) error {
	// Get monthly usage by the following iterations:
	// Example documents for monthly rollups:
	//   pk: 1:2024:5 => Usage (all SKUs) for May 2024.
	//   id: 1:copilot_standalone:2024:5:25 => Copilot Standalone usage for May 25, 2024.
	//
	// Example documents for monthly rollups for product:
	//   pk: 1:copilot:2024:5 => Copilot usage (all Copilot SKUs) for May 2024.
	//   id: 1:copilot_standalone:2024:5:25 => Copilot Standalone usage for May 25, 2024.
	//
	// Example documents for monthly rollups for sku:
	//   pk: 1:copilot_standalone:2024:5 => Copilot usage for copilot_standalone sku for May 2024.
	//   id: 1:copilot_standalone:2024:5:25 => Copilot Standalone usage for May 25, 2024.
	//
	// Example documents for monthly rollups for byProductSku:
	//   pk: 1:org:2:2024:5:byProductSku => Usage (all SKUs) for org 2 for May 2024.
	//   id: 1:copilot_standalone:2024:5:25 => Copilot Standalone usage for org 2 for May 25, 2024
	//
	// Example documents for monthly rollups for byOrgRepoProductSku:
	//   pk: 1:2024:5:byOrgRepoProductSku => Usage (all SKUs) sku for May 2024.
	//   id: customer:1:org:2:repo:3:product:copilot:sku:copilot_standalone:2024:5:25 => Copilot Standalone usage for org 2 repo 3 for May 25, 2024
	//
	monthlyPartitionDetail := &models.UsagePartitionDetail{
		UsageEntityId: customer.GetCustomerId(),
		UsageTime:     models.NewUsageTime().WithYear(year).WithMonth(time.Month(month)),
		ActiveType:    models.Monthly,
	}

	if runType == ByProduct {
		monthlyPartitionDetail = &models.UsagePartitionDetail{
			UsageEntityId: customer.GetCustomerId(),
			UsageTime:     models.NewUsageTime().WithYear(year).WithMonth(time.Month(month)),
			Product:       product,
			ActiveType:    models.Monthly,
		}
	}

	if runType == BySku {
		monthlyPartitionDetail = &models.UsagePartitionDetail{
			UsageEntityId: customer.GetCustomerId(),
			UsageTime:     models.NewUsageTime().WithYear(year).WithMonth(time.Month(month)),
			Sku:           sku,
			ActiveType:    models.Monthly,
		}
	}

	if runType == ByProductSku {
		monthlyPartitionDetail = &models.UsagePartitionDetail{
			UsageEntityId: customer.GetCustomerId(),
			UsageTime:     models.NewUsageTime().WithYear(year).WithMonth(time.Month(month)),
			ActiveType:    models.Monthly,
			OrgId:         orgId,
			GroupBy:       models.ByProductSkuGrouping,
		}
	}

	if runType == ByOrgRepoProductSku {
		monthlyPartitionDetail = &models.UsagePartitionDetail{
			UsageEntityId: customer.GetCustomerId(),
			UsageTime:     models.NewUsageTime().WithYear(year).WithMonth(time.Month(month)),
			ActiveType:    models.Monthly,
			GroupBy:       models.ByOrgRepoProductSkuGrouping,
		}
	}

	monthlyUsageLineItems, err := t.usageEngine.GetLineItems(t.ctx, logger, monthlyPartitionDetail)
	if err != nil {
		return err
	}

	logger.Info("Monthly usage line items found", kvp.Int("gh.billing_platform.transition.line_items_found", len(monthlyUsageLineItems)), kvp.String("db.cosmosdb.partition_key", monthlyPartitionDetail.ToGetLineItemsPartitionKey()))

	lineItemRateLimit := ratelimit.New(100) // 100 line items per second
	prev := time.Now()
	for _, monthlyUsageLineItem := range monthlyUsageLineItems {
		now := lineItemRateLimit.Take()

		if monthlyUsageLineItem.Pricing.Product != product {
			continue
		}

		if monthlyUsageLineItem.Pricing.Sku != sku {
			continue
		}

		if runType == ByOrgRepoProductSku {
			if monthlyUsageLineItem.EntityDetail.OrganizationId != orgId {
				continue
			}
		}

		monthlyBilledAmount := int64(0)
		monthlyQuantity := int64(0)
		monthlyFractionalQuantity := int64(0)
		monthlyFullQuantity := int64(0)

		logger.Info("Running transition on monthly line item",
			kvp.String("db.cosmosdb.partition_key", monthlyUsageLineItem.Key.PartitionKey),
			kvp.String("db.cosmosdb.id", monthlyUsageLineItem.Id),
		)

		logger.Info("Monthly rollup before result",
			kvp.String("db.cosmosdb.partition_key", monthlyPartitionDetail.ToGetLineItemsPartitionKey()),
			kvp.String("db.cosmosdb.id", monthlyUsageLineItem.Id),
			kvp.Int64("gh.billing_platform.transition.monthly_billed_amount", monthlyUsageLineItem.BilledAmount),
			kvp.Int64("gh.billing_platform.transition.monthly_quantity", monthlyUsageLineItem.Quantity),
			kvp.Int64("gh.billing_platform.transition.monthly_fractional_quantity", monthlyUsageLineItem.FractionalQuantity),
			kvp.Int64("gh.billing_platform.transition.monthly_full_quantity", monthlyUsageLineItem.FullQuantity),
		)
		logger.Info("Monthly rollup after result",
			kvp.String("db.cosmosdb.partition_key", monthlyPartitionDetail.ToGetLineItemsPartitionKey()),
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
			logger.Info("Successfully updated monthly rollup", kvp.String("db.cosmosdb.partition_key", monthlyPartitionDetail.ToGetLineItemsPartitionKey()))
		}

		logger.Info(fmt.Sprintf("Duration: %s", now.Sub(prev)))
		prev = now
	}

	return nil
}

func (t *CorrectUsageTransition) correctYearlyUsage(logger log.Logger, customer *models.Customer, product string, sku string, year int64, orgId int64, dryRun bool, runType string) error {
	// Get yearly usage by the following iterations:
	// Example documents for yearly rollups:
	//   pk: 1:2024 => Usage (all SKUs) for 2024.
	//   id: 1:copilot_standalone:2024:5 => Copilot Standalone usage for May 2024.
	//
	// Example documents for yearly rollups for product:
	//   pk: 1:copilot:2024 => Copilot usage (all Copilot SKUs) for 2024.
	//   id: 1:copilot_standalone:2024:5 => Copilot Standalone usage for May 2024.
	//
	// Example documents for yearly rollups for sku:
	//   pk: 1:copilot_standalone:2024 => Copilot usage for copilot_standalone sku for 2024.
	//   id: 1:copilot_standalone:2024:5 => Copilot Standalone usage for May 2024.
	//
	// Example documents for yearly rollups for byProductSku:
	//   pk: 1:org:2:2024:yProductSku => Usage (all SKUs) for org 2 for 2024.
	//   id: 1:copilot_standalone:2024:5 => Copilot Standalone usage for org 2 for May 2024
	//
	// Example documents for yearly rollups for byOrgRepoProductSku:
	//   pk: 1:2024:byOrgRepoProductSku => Usage (all SKUs) sku for 2024.
	//   id: customer:1:org:2:repo:3:product:copilot:sku:copilot_standalone:2024:5 => Copilot Standalone usage for org 2 repo 3 for May 2024
	//
	yearlyPartitionDetail := &models.UsagePartitionDetail{
		UsageEntityId: customer.GetCustomerId(),
		UsageTime:     models.NewUsageTime().WithYear(year),
		ActiveType:    models.Yearly,
	}

	if runType == ByProduct {
		yearlyPartitionDetail = &models.UsagePartitionDetail{
			UsageEntityId: customer.GetCustomerId(),
			UsageTime:     models.NewUsageTime().WithYear(year),
			Product:       product,
			ActiveType:    models.Yearly,
		}
	}

	if runType == BySku {
		yearlyPartitionDetail = &models.UsagePartitionDetail{
			UsageEntityId: customer.GetCustomerId(),
			UsageTime:     models.NewUsageTime().WithYear(year),
			Sku:           sku,
			ActiveType:    models.Yearly,
		}
	}

	if runType == ByProductSku {
		yearlyPartitionDetail = &models.UsagePartitionDetail{
			UsageEntityId: customer.GetCustomerId(),
			UsageTime:     models.NewUsageTime().WithYear(year),
			ActiveType:    models.Yearly,
			OrgId:         orgId,
			GroupBy:       models.ByProductSkuGrouping,
		}
	}

	if runType == ByOrgRepoProductSku {
		yearlyPartitionDetail = &models.UsagePartitionDetail{
			UsageEntityId: customer.GetCustomerId(),
			UsageTime:     models.NewUsageTime().WithYear(year),
			ActiveType:    models.Yearly,
			GroupBy:       models.ByOrgRepoProductSkuGrouping,
		}
	}

	yearlyUsageLineItems, err := t.usageEngine.GetLineItems(t.ctx, logger, yearlyPartitionDetail)
	if err != nil {
		return err
	}

	logger.Info("Yearly usage line items found", kvp.Int("gh.billing_platform.transition.line_items_found", len(yearlyUsageLineItems)), kvp.String("db.cosmosdb.partition_key", yearlyPartitionDetail.ToGetLineItemsPartitionKey()))

	lineItemRateLimit := ratelimit.New(100) // 100 line items per second
	prev := time.Now()
	for _, yearlyUsageLineItem := range yearlyUsageLineItems {
		now := lineItemRateLimit.Take()

		if yearlyUsageLineItem.Pricing.Product != product {
			continue
		}

		if yearlyUsageLineItem.Pricing.Sku != sku {
			continue
		}

		if runType == ByOrgRepoProductSku {
			if yearlyUsageLineItem.EntityDetail.OrganizationId != orgId {
				continue
			}
		}

		yearlyBilledAmount := int64(0)
		yearlyQuantity := int64(0)
		yearlyFractionalQuantity := int64(0)
		yearlyFullQuantity := int64(0)

		logger.Info("Running transition on yearly line item",
			kvp.String("db.cosmosdb.partition_key", yearlyUsageLineItem.Key.PartitionKey),
			kvp.String("db.cosmosdb.id", yearlyUsageLineItem.Id),
		)

		logger.Info("Yearly rollup before result",
			kvp.String("db.cosmosdb.partition_key", yearlyPartitionDetail.ToGetLineItemsPartitionKey()),
			kvp.String("db.cosmosdb.id", yearlyUsageLineItem.Id),
			kvp.Int64("gh.billing_platform.transition.yearly_billed_amount", yearlyUsageLineItem.BilledAmount),
			kvp.Int64("gh.billing_platform.transition.yearly_quantity", yearlyUsageLineItem.Quantity),
			kvp.Int64("gh.billing_platform.transition.yearly_fractional_quantity", yearlyUsageLineItem.FractionalQuantity),
			kvp.Int64("gh.billing_platform.transition.yearly_full_quantity", yearlyUsageLineItem.FullQuantity),
		)
		logger.Info("Yearly rollup after result",
			kvp.String("db.cosmosdb.partition_key", yearlyPartitionDetail.ToGetLineItemsPartitionKey()),
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
			logger.Info("Successfully updated yearly rollup", kvp.String("db.cosmosdb.partition_key", yearlyPartitionDetail.ToGetLineItemsPartitionKey()))
		}

		logger.Info(fmt.Sprintf("Duration: %s", now.Sub(prev)))
		prev = now
	}

	return nil
}
