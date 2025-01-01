package transitions

import (
	"context"
	"fmt"
	"time"

	"github.com/pkg/errors"
	"golang.org/x/sync/errgroup"

	"github.com/github/billing-platform/internal/logging"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

type DeleteByOrgRepoProductSKUTransition struct {
	ctx              context.Context
	cfg              *config.Config
	logger           log.Logger
	customerEngine   engines.CustomerEngineInterface
	costCenterEngine engines.CostCenterEngineInterface
	usageEngine      engines.UsageEngineInterface
	db               interfaces.Database
}

func NewDeleteByOrgRepoProductSKUTransition(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	customerEngine engines.CustomerEngineInterface,
	costCenterEngine engines.CostCenterEngineInterface,
	usageEngine engines.UsageEngineInterface,
	db interfaces.Database,
) *DeleteByOrgRepoProductSKUTransition {
	return &DeleteByOrgRepoProductSKUTransition{
		ctx:              ctx,
		cfg:              cfg,
		logger:           logger,
		customerEngine:   customerEngine,
		costCenterEngine: costCenterEngine,
		usageEngine:      usageEngine,
		db:               db,
	}
}

func (t *DeleteByOrgRepoProductSKUTransition) Run(dryRun bool, customerIDList []string) error {
	for _, customerID := range customerIDList {
		t.logger.Info("Running byOrgRepoProductSKU transition...", kvp.String(logging.BillingCustomerId, customerID))

		err := t.RunTransitionForCustomer(dryRun, customerID)
		if err != nil {
			return err
		}
	}

	return nil
}

func (t *DeleteByOrgRepoProductSKUTransition) RunTransitionForCustomer(dryRun bool, customerID string) error {
	customer, err := t.customerEngine.Get(t.ctx, t.logger, customerID, false)
	if err != nil {
		return err
	}

	if customer == nil {
		return fmt.Errorf("customer not found: %s", customerID)
	}

	err = t.DeleteByOrgRepoProductSKU(dryRun, customer)
	if err != nil {
		return err
	}

	// The customer might have cost centers that we will have to iterate through and submit line items for
	// TODO: Replace all occurrences of 'bpErr' with 'err' to handle errors throughout the code.
	// we will replace the standard error package with the bperrors package and use
	// the err variable to handle errors throughout the code.
	costCenters, bpErr := t.costCenterEngine.GetAllCostCenters(t.ctx, t.logger, customer)
	if bpErr != nil {
		return errors.New(bpErr.Error())
	}

	t.logger.Info("Running transition on cost center items...")
	for _, costCenter := range costCenters {
		costCenterCustomer, err := t.customerEngine.Get(t.ctx, t.logger, costCenter.CostCenterKey.UUID, false)
		if err != nil {
			return err
		}

		if costCenterCustomer == nil {
			return errors.New("cost center customer not found")
		}

		err = t.DeleteByOrgRepoProductSKU(dryRun, costCenterCustomer)
		if err != nil {
			return err
		}
	}

	return nil
}

func (t *DeleteByOrgRepoProductSKUTransition) DeleteByOrgRepoProductSKU(dryRun bool, customer *models.Customer) error {
	err := t.RemoveByOrgRepoProductSKU(dryRun, customer)
	if err != nil {
		return errors.Wrap(err, "failed to delete byOrgRepoProductSKU items")
	}

	err = t.RemoveByOrgRepoProductSKUDiscounts(dryRun, customer)
	if err != nil {
		return errors.Wrap(err, "failed to delete byOrgRepoProductSKU discount items")
	}

	return nil
}

func (t *DeleteByOrgRepoProductSKUTransition) RemoveByOrgRepoProductSKU(dryRun bool, customer *models.Customer) error {
	options := &interfaces.QueryOptions{
		RetryCount: 10,
	}

	partitionDetail := &models.UsagePartitionDetail{
		UsageEntityId: customer.GetCustomerId(),
		UsageTime:     models.NewUsageTime().WithYear(2023),
		ActiveType:    models.Yearly,
		GroupBy:       "byOrgRepoProductSku",
	}

	monthlyUsageLineItems, err := t.usageEngine.GetLineItems(t.ctx, t.logger, partitionDetail)
	if err != nil {
		return err
	}

	if !dryRun {
		for _, monthlyUsageLineItem := range monthlyUsageLineItems {
			err = t.db.DeleteWithOptions(t.ctx, t.logger, &monthlyUsageLineItem.Key, options)
			if err != nil {
				return err
			}
		}
	}

	for month := 8; month <= 12; month++ {
		partitionDetail := &models.UsagePartitionDetail{
			UsageEntityId: customer.GetCustomerId(),
			UsageTime:     models.NewUsageTime().WithYear(2023).WithMonth(time.Month(month)),
			ActiveType:    models.Monthly,
			GroupBy:       "byOrgRepoProductSku",
		}

		dailyUsageLineItems, err := t.usageEngine.GetLineItems(t.ctx, t.logger, partitionDetail)
		if err != nil {
			return err
		}

		if !dryRun {
			for _, dailyUsageLineItem := range dailyUsageLineItems {
				err = t.db.DeleteWithOptions(t.ctx, t.logger, &dailyUsageLineItem.Key, options)
				if err != nil {
					return err
				}
			}
		}

		for day := 1; day <= 31; day++ {
			partitionDetail := &models.UsagePartitionDetail{
				UsageEntityId: customer.GetCustomerId(),
				UsageTime:     models.NewUsageTime().WithYear(2023).WithMonth(time.Month(month)).WithDay(day),
				ActiveType:    models.Daily,
				GroupBy:       "byOrgRepoProductSku",
			}

			hourlyUsageLineItems, err := t.usageEngine.GetLineItems(t.ctx, t.logger, partitionDetail)
			if err != nil {
				return err
			}

			if !dryRun {
				for _, hourlyUsageLineItem := range hourlyUsageLineItems {
					err = t.db.DeleteWithOptions(t.ctx, t.logger, &hourlyUsageLineItem.Key, options)
					if err != nil {
						return err
					}
				}
			}

			for hour := 0; hour <= 23; hour++ {
				partitionDetail := &models.UsagePartitionDetail{
					UsageEntityId: customer.GetCustomerId(),
					UsageTime:     models.NewUsageTime().WithYear(2023).WithMonth(time.Month(month)).WithDay(day).WithHour(hour),
					ActiveType:    models.Hourly,
					GroupBy:       "byOrgRepoProductSku",
				}

				rawUsageLineItems, err := t.usageEngine.GetLineItems(t.ctx, t.logger, partitionDetail)
				if err != nil {
					return err
				}

				errs, gctx := errgroup.WithContext(t.ctx)
				for _, rawUsageLineItem := range rawUsageLineItems {
					localRawUsageLineItem := rawUsageLineItem

					errs.Go(func() error {
						if !dryRun {
							err := t.db.DeleteWithOptions(gctx, t.logger, &localRawUsageLineItem.Key, options)
							if err != nil {
								return err
							}
						}

						return nil
					})
				}

				if err := errs.Wait(); err != nil {
					return errors.Wrap(err, "failed to delete ByOrgRepoProductSku line items")
				}
			}
		}
	}

	return nil
}

func (t *DeleteByOrgRepoProductSKUTransition) RemoveByOrgRepoProductSKUDiscounts(dryRun bool, customer *models.Customer) error {
	options := &interfaces.QueryOptions{
		RetryCount: 10,
	}

	partitionDetail := &models.UsagePartitionDetail{
		UsageEntityId: customer.GetCustomerId(),
		UsageTime:     models.NewUsageTime().WithYear(2023),
		ActiveType:    models.Yearly,
		GroupBy:       "byOrgRepoProductSku",
	}

	monthlyDiscountLineItems, err := t.usageEngine.GetDiscountLineItemsFromPartitionKey(t.ctx, t.logger, models.GetDiscountPartitionKey(partitionDetail.ToGetLineItemsPartitionKey()))
	if err != nil {
		return err
	}

	if !dryRun {
		for _, monthlyDiscountLineItem := range monthlyDiscountLineItems {
			err := t.db.DeleteWithOptions(t.ctx, t.logger, monthlyDiscountLineItem.Key, options)
			if err != nil {
				return err
			}
		}
	}

	for month := 8; month <= 12; month++ {
		partitionDetail := &models.UsagePartitionDetail{
			UsageEntityId: customer.GetCustomerId(),
			UsageTime:     models.NewUsageTime().WithYear(2023).WithMonth(time.Month(month)),
			ActiveType:    models.Monthly,
			GroupBy:       "byOrgRepoProductSku",
		}

		dailyDiscountLineItems, err := t.usageEngine.GetDiscountLineItemsFromPartitionKey(t.ctx, t.logger, models.GetDiscountPartitionKey(partitionDetail.ToGetLineItemsPartitionKey()))
		if err != nil {
			return err
		}

		if !dryRun {
			for _, dailyDiscountLineItem := range dailyDiscountLineItems {
				err := t.db.DeleteWithOptions(t.ctx, t.logger, dailyDiscountLineItem.Key, options)
				if err != nil {
					return err
				}
			}
		}

		for day := 1; day <= 31; day++ {
			partitionDetail := &models.UsagePartitionDetail{
				UsageEntityId: customer.GetCustomerId(),
				UsageTime:     models.NewUsageTime().WithYear(2023).WithMonth(time.Month(month)).WithDay(day),
				ActiveType:    models.Daily,
				GroupBy:       "byOrgRepoProductSku",
			}

			hourlyDiscountLineItems, err := t.usageEngine.GetDiscountLineItemsFromPartitionKey(t.ctx, t.logger, models.GetDiscountPartitionKey(partitionDetail.ToGetLineItemsPartitionKey()))
			if err != nil {
				return err
			}

			if !dryRun {
				for _, hourlyDiscountLineItem := range hourlyDiscountLineItems {
					err := t.db.DeleteWithOptions(t.ctx, t.logger, hourlyDiscountLineItem.Key, options)
					if err != nil {
						return err
					}
				}
			}

			for hour := 0; hour <= 23; hour++ {
				partitionDetail := &models.UsagePartitionDetail{
					UsageEntityId: customer.GetCustomerId(),
					UsageTime:     models.NewUsageTime().WithYear(2023).WithMonth(time.Month(month)).WithDay(day).WithHour(hour),
					ActiveType:    models.Hourly,
					GroupBy:       "byOrgRepoProductSku",
				}

				rawDiscountLineItems, err := t.usageEngine.GetDiscountLineItemsFromPartitionKey(t.ctx, t.logger, models.GetDiscountPartitionKey(partitionDetail.ToGetLineItemsPartitionKey()))
				if err != nil {
					return err
				}

				errs, gctx := errgroup.WithContext(t.ctx)
				for _, rawDiscountLineItem := range rawDiscountLineItems {
					localRawDiscountLineItem := rawDiscountLineItem

					errs.Go(func() error {
						if !dryRun {
							err := t.db.DeleteWithOptions(gctx, t.logger, localRawDiscountLineItem.Key, options)
							if err != nil {
								return err
							}
						}

						return nil
					})
				}

				if err := errs.Wait(); err != nil {
					return errors.Wrap(err, "failed to delete ByOrgRepoProductSku discount line items")
				}
			}
		}
	}

	return nil
}
