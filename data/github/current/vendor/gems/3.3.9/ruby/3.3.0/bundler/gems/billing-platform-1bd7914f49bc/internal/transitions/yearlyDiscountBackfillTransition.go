package transitions

import (
	"context"
	"fmt"
	"time"

	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/log"
)

type YearlyDiscountBackfillTransition struct {
	ctx              context.Context
	cfg              *config.Config
	logger           log.Logger
	customerEngine   *engines.CustomerEngine
	costCenterEngine engines.CostCenterEngineInterface
	usageEngine      *engines.UsageEngine
	db               interfaces.Database
}

func NewYearlyDiscountBackfillTransition(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	customerEngine *engines.CustomerEngine,
	costCenterEngine engines.CostCenterEngineInterface,
	usageEngine *engines.UsageEngine,
	db interfaces.Database,
) *YearlyDiscountBackfillTransition {
	return &YearlyDiscountBackfillTransition{
		ctx:              ctx,
		cfg:              cfg,
		logger:           logger,
		customerEngine:   customerEngine,
		costCenterEngine: costCenterEngine,
		usageEngine:      usageEngine,
		db:               db,
	}
}

func (t *YearlyDiscountBackfillTransition) Run(dryRun bool, customerID string) error {
	t.logger.Info("Running yearly discount backfill transition...")

	customer, err := t.customerEngine.Get(t.ctx, t.logger, customerID)
	if err != nil {
		return err
	}

	// delete current items in the customer's yearly discount partition
	err = t.DeleteYearlyDiscountPartitionItems(dryRun, customer)
	if err != nil {
		return err
	}

	// get all the monthly discount line items for the customer and create the yearly discount line items
	err = t.GetAndCreateDiscountRollups(dryRun, customer, time.August)
	if err != nil {
		return err
	}

	err = t.GetAndCreateDiscountRollups(dryRun, customer, time.September)
	if err != nil {
		return err
	}

	// The customer might have cost centers that we will have to iterate through
	// TODO: Replace all occurrences of 'bpErr' with 'err' to handle errors throughout the code.
	// we will replace the standard error package with the bperrors package and use
	// the err variable to handle errors throughout the code.
	costCenters, bpErr := t.costCenterEngine.GetAllCostCenters(t.ctx, t.logger, customer)
	if bpErr != nil {
		return bpErr
	}

	for _, costCenter := range costCenters {
		t.logger.Info("Updating cost center yearly discount partitions...")

		costCenterCustomer, err := t.customerEngine.Get(t.ctx, t.logger, costCenter.CostCenterKey.UUID)
		if err != nil {
			t.logger.WithError(err).Error("failed to get cost center customer")
			continue
		}

		if costCenterCustomer == nil {
			t.logger.Info("Cost center customer not found")
			continue
		}

		// delete current items in the cost center's yearly discount partition
		err = t.DeleteYearlyDiscountPartitionItems(dryRun, costCenterCustomer)
		if err != nil {
			return err
		}

		// get all the monthly discount line items for the cost center and create the yearly discount line items
		err = t.GetAndCreateDiscountRollups(dryRun, costCenterCustomer, time.August)
		if err != nil {
			return err
		}

		err = t.GetAndCreateDiscountRollups(dryRun, costCenterCustomer, time.September)
		if err != nil {
			return err
		}
	}

	t.logger.Info("Finished running yearly discount backfill transition")

	return nil
}

func (t *YearlyDiscountBackfillTransition) DeleteYearlyDiscountPartitionItems(dryRun bool, customer *models.Customer) error {
	usageTime := models.NewUsageTime().WithYear(2023)
	usagePartitionDetail := &models.UsagePartitionDetail{
		UsageEntityId: customer.GetCustomerId(),
		UsageTime:     usageTime,
		ActiveType:    models.Yearly,
	}

	discountLineItems, err := t.usageEngine.GetDiscountLineItems(t.ctx, t.logger, usagePartitionDetail)
	if err != nil {
		return err
	}

	// delete items in customerID:year:discount partition
	for _, discountLineItem := range discountLineItems {
		t.logger.Info("Deleting yearly customer discount line item")

		if !dryRun {
			err = t.db.DeleteWithOptions(t.ctx, t.logger, discountLineItem.Key, nil)
			if err != nil {
				return err
			}
		}

		// delete items in customerID:[sku]:year:discount partition
		usagePartitionDetail = &models.UsagePartitionDetail{
			UsageEntityId: customer.GetCustomerId(),
			UsageTime:     usageTime,
			Sku:           discountLineItem.Pricing.Sku,
			ActiveType:    models.Yearly,
		}

		discountSkuLineItems, err := t.usageEngine.GetDiscountLineItems(t.ctx, t.logger, usagePartitionDetail)
		if err != nil {
			return err
		}

		for _, discountSkuLineItem := range discountSkuLineItems {
			t.logger.Info("Deleting yearly customer SKU discount line item")

			if !dryRun {
				err = t.db.DeleteWithOptions(t.ctx, t.logger, discountSkuLineItem.Key, nil)
				if err != nil {
					return err
				}
			}
		}
	}

	return nil
}

func (t *YearlyDiscountBackfillTransition) GetAndCreateDiscountRollups(dryRun bool, customer *models.Customer, month time.Month) error {
	discountItemMap := make(map[string]*models.DiscountItem)

	usageTime := models.NewUsageTime().WithYear(2023).WithMonth(month)

	usagePartitionDetail := &models.UsagePartitionDetail{
		UsageEntityId: customer.GetCustomerId(),
		UsageTime:     usageTime,
		ActiveType:    models.Monthly,
	}

	discountLineItems, err := t.usageEngine.GetDiscountLineItems(t.ctx, t.logger, usagePartitionDetail)
	if err != nil {
		return err
	}

	for _, discountLineItem := range discountLineItems {
		t.logger.Info("Processing discount line item")

		// Accumulate all the discount line items for a given SKU into a map
		_, ok := discountItemMap[discountLineItem.Pricing.Sku]
		if ok {
			discountItemMap[discountLineItem.Pricing.Sku].DiscountAmount += discountLineItem.DiscountAmount
			discountItemMap[discountLineItem.Pricing.Sku].Quantity += discountLineItem.Quantity
		} else {
			discountItemMap[discountLineItem.Pricing.Sku] = discountLineItem
		}
	}

	for key, discountItem := range discountItemMap {
		// Convert the monthly discount item into a yearly discount item and write the new record
		discountItem.Id = fmt.Sprintf("%s:%s:%d:%d:discount", customer.GetCustomerId(), key, 2023, month)
		discountItem.PartitionKey = fmt.Sprintf("%s:%d:discount", customer.GetCustomerId(), 2023)
		discountItem.Key.Id = discountItem.Id
		discountItem.Key.PartitionKey = discountItem.PartitionKey
		t.logger.Info("Creating yearly discount item by customer")
		if !dryRun {
			err = t.db.CreateWithOptions(t.ctx, t.logger, discountItem, nil)
			if err != nil {
				t.logger.WithError(err).Error("failed to create yearly discount item by customer")
			}
		}

		// Convert the monthly discount item into a yearly discount item with SKU and write the new record
		discountItem.Id = fmt.Sprintf("%s:%s:%d:%d:discount", customer.GetCustomerId(), key, 2023, month)
		discountItem.PartitionKey = fmt.Sprintf("%s:%s:%d:discount", customer.GetCustomerId(), key, 2023)
		discountItem.Key.Id = discountItem.Id
		discountItem.Key.PartitionKey = discountItem.PartitionKey
		t.logger.Info("Creating yearly discount item by customer SKU")
		if !dryRun {
			err = t.db.CreateWithOptions(t.ctx, t.logger, discountItem, nil)
			if err != nil {
				t.logger.WithError(err).Error("failed to create yearly discount item by customer SKU")
			}
		}
	}

	return nil
}
