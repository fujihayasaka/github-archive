package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/engines"
	stats "github.com/github/go-stats"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/internal/featureflags"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
)

var (
	cachedEnabledCustomerIDs []string
	cacheEmissionRWMutex     sync.RWMutex
	once                     sync.Once
)

type EmissionHandler struct {
	*Handler
	customerEngine   engines.CustomerEngineInterface
	costCenterEngine engines.CostCenterEngineInterface
	usageEngine      engines.UsageEngineInterface
	zuoraEngine      engines.ZuoraEngineInterface
}

func NewEmissionHandler(
	params *HandlerParams,
	customerEngine engines.CustomerEngineInterface,
	costCenterEngine engines.CostCenterEngineInterface,
	usageEngine engines.UsageEngineInterface,
	zuoraEngine engines.ZuoraEngineInterface,
) *EmissionHandler {
	return &EmissionHandler{
		Handler:          NewHandler(params, models.WorkerTypeEmissionHandler),
		customerEngine:   customerEngine,
		costCenterEngine: costCenterEngine,
		usageEngine:      usageEngine,
		zuoraEngine:      zuoraEngine,
	}
}

func (h *EmissionHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	logger.Debug("Processing message in", kvp.String("queue", h.queueName))
	logger.Debug("unmarshalling enveloped message", kvp.String("payload", string(rr.Payload)))

	start := time.Now()
	defer func() {
		duration := time.Since(start)
		h.statter.Timing("emission-handler.processing-time", stats.Tags{}, duration)
	}()

	logger.Debug("unmarshalling enveloped message", kvp.String("payload", string(rr.Payload)))

	var items []*models.Item
	if err := json.Unmarshal(rr.Payload, &items); err != nil {
		h.TrackEmissionErrorAndAddToDLQ(ctx, logger, rr, "unmarshal_error", errors.Wrap(err, "failed to unmarshal enveloped message"))
		return nil
	}

	if len(items) == 0 || items[0] == nil {
		h.TrackEmissionErrorAndAddToDLQ(ctx, logger, rr, "unmarshal_error", errors.New("no items found in the enveloped message"))
		return nil
	}

	firstUsageItem := items[0]

	// A few validations that will apply to all emissions items.
	customer, enterpriseCustomer, err := h.customerEngine.GetBillingAndParentCustomersFromCustomerId(ctx, logger, firstUsageItem.GetCustomerId())
	if err != nil {
		logger.WithError(err).Error("failed to retrieve customer and enterprise customer")
		return err
	}

	if customer == nil {
		logger.WithError(err).Error("failed to retrieve customer")
		return errors.New("failed to retrieve customer")
	}

	if enterpriseCustomer == nil {
		logger.WithError(err).Error("failed to retrieve enterprise customer")
		return errors.New("failed to retrieve enterprise customer")
	}

	// Determine if this is to go Azure or Zuora path

	switch customer.BillingTarget {
	case models.Azure:
		// NOTE - When doing the Azure Path, We need to send usage by (Customer and SKU)
		// to Azure in separate sends
		// This is where the Azure Process will start
		// if err := h.processAzureEmission(ctx, logger, actUsageItem); err != nil {
		// 	h.TrackEmissionErrorAndAddToDLQ(ctx, logger, rr, "azure_emission_error", errors.Wrap(err, "failed to process azure emission"))
		// }
	case models.Zuora:
		// NOTE - When doing the Zuora Path, We need to send usage by Customer in a single
		// send to Zuora
		if err := h.processZuoraEmission(ctx, logger, customer, enterpriseCustomer, items); err != nil {
			h.TrackEmissionErrorAndAddToDLQ(ctx, logger, rr, "zuora_emission_error", errors.Wrap(err, "failed to process zuora emission"),
				kvp.String("customer_id", customer.GetCustomerId()))
		}
	}
	return nil
}

func (h *EmissionHandler) processZuoraEmission(ctx context.Context, logger log.Logger, customer *models.Customer, enterpriseCustomer *models.Customer, items []*models.Item) error {
	start := time.Now()
	defer func() {
		duration := time.Since(start)
		h.statter.Timing("emission_handler_zuora_fanout", stats.Tags{}, duration)
	}()

	// All Processing put behind a feature flag
	if !h.shouldProcessEmission(ctx, logger, customer) {
		return nil
	}

	// Set the emission date to yesterday
	emissionDateTime := *models.NewUsageTimeFromTime(models.UTCNow().AddDate(0, 0, -1))

	emissions, err := h.generateEmission(ctx, logger, emissionDateTime, items, customer, enterpriseCustomer)
	if err != nil {
		logger.WithError(err).Error("error generating emission")
		return err
	}

	err = h.zuoraEngine.ProcessDailyZuoraBatch(ctx, logger, emissionDateTime, customer, enterpriseCustomer, emissions)
	if err != nil {
		logger.WithError(err).Error("error processing daily zuora batch")
		return err
	}

	logger.Info("emission dispatcher zuora fanout finished")

	return nil
}

func (h *EmissionHandler) generateEmission(ctx context.Context, logger log.Logger, emissionDateTime models.UsageTime, items []*models.Item, customer *models.Customer, enterpriseCustomer *models.Customer) (*models.Emission, error) {

	emissionTargetDate := &models.EmissionTarget{
		Year:  int64(emissionDateTime.Year()),
		Month: int64(emissionDateTime.Month()),
		Day:   int64(emissionDateTime.Day()),
	}
	// Get the key for the partition to search by emission date
	dailyUsagePartitionDetail, err := models.GetPartitionDetailForDailyRollups(emissionTargetDate, customer.GetCustomerId())
	if err != nil {
		logger.WithError(err).Error("failed to create usage partition detail for emission generation")
		return nil, err
	}

	// filter usage by customer and validate usage items for emission
	validatedUsageItems, err := h.ValidateUsageItems(ctx, logger, customer, items)
	if err != nil {
		return nil, errors.Wrap(err, "failed to validate usage items for emission generation")
	}

	discountItems, err := h.usageEngine.GetDiscountLineItems(ctx, logger, dailyUsagePartitionDetail)
	if err != nil {
		return nil, errors.Wrap(err, "failed to retrieve discount line items for emission generation")
	}

	// Process late usage items and discount items
	combinedDiscountItems, err := h.includeLateDiscountItems(ctx, logger, customer, discountItems, emissionDateTime)
	if err != nil {
		return nil, errors.Wrap(err, "failed to retrieve late usage discount line items for emission generation")
	}

	// Pull in the discounts and other checks.
	// If a customer was offboarded from Copilot, we need to filter out any
	// Copilot usage since we track usage per month but we don't know how much
	// they actually used until they were offboarded.
	// Since we can't tell if they were ever onboarded to
	// Copilot, the best we can do is check if Copilot is disabled now.

	var finalUsageItems []*models.Item
	var finalDiscountItems []*models.DiscountItem
	if !customer.HasEnabledProduct("copilot") {
		finalUsageItems = h.rejectItemsByProduct(validatedUsageItems, "copilot")
		finalDiscountItems = h.rejectDiscountItemsByProduct(combinedDiscountItems, "copilot")
	} else {
		finalUsageItems = validatedUsageItems
		finalDiscountItems = combinedDiscountItems
	}

	emissionPartitionDetail, err := models.GetPartitionDetailForEmission(emissionTargetDate, customer.GetCustomerId())
	if err != nil {
		logger.WithError(err).Error("failed to create emission partition detail for emission generation")
		return nil, err
	}

	// Look up the cost center if the customer is a cost center proxy
	var costCenter *models.CostCenter
	if customer.IsCostCenterProxy {
		costCenterKey := &models.CostCenterKey{
			Key: &models.Key{
				PartitionKey: enterpriseCustomer.ToCostCentersPartitionKey(),
				Id:           customer.CostCenterUUID,
			},
		}

		costCenter, err = h.costCenterEngine.Get(ctx, logger, costCenterKey)

		if err != nil {
			return nil, errors.Wrap(err, "failed to get cost center")
		} else if costCenter == nil {
			return nil, fmt.Errorf("no cost center found")
		}
	}

	// partitionKey=customer:id:Emissions, id=customer:id:Emission:year:month:day
	emission := models.NewEmission(emissionPartitionDetail, finalUsageItems, finalDiscountItems, costCenter)

	// Do a upsert on the emissions
	_, err = h.zuoraEngine.UpsertEmission(ctx, logger, emission)
	if err != nil {
		return nil, errors.Wrap(err, "failed to generate emissions")
	}

	return emission, nil

}

func (h *EmissionHandler) shouldProcessEmission(ctx context.Context, logger log.Logger, customer *models.Customer) bool {

	processEmission := false
	runningDate := time.Now()

	// Check for existing customer IDs in the configuration
	if h.cfg.CustomersWithDailyEmissionEnabled != "" {
		enabledCustomerIDs := h.getEnabledCustomerIDs(h.cfg.CustomersWithDailyEmissionEnabled)
		if slices.Contains(enabledCustomerIDs, customer.GetCustomerId()) {
			logger.Info("Customer ID enabled for daily emission in existing configuration")
			processEmission = true
			return processEmission
		}
	}

	activeDate, err := time.Parse("2006-01-02", h.cfg.DailyEmissionsActiveDate)
	if err != nil {
		logger.Error("Invalid format for DailyEmissionsActiveDate")
		return processEmission
	}

	// Check if the current running date is equal to or greater than DailyEmissionsActiveDate
	if runningDate.Before(activeDate) {
		logger.Info("Current date is before the active date for daily emissions")
		return processEmission
	}

	// Check new customer to begin on March 1st
	isFeatureFlagEnabled := h.flagger.IsEnabledWithDefaultValue(ctx, featureflags.ShouldProcessZuoraDailyEmission, false, models.CustomerVexiActor(customer.GetCustomerId()))
	if isFeatureFlagEnabled {
		logger.Info("Feature flag for processing zuora daily emission is enabled")
		processEmission = true
	}

	return processEmission
}

func (h *EmissionHandler) TrackEmissionErrorAndAddToDLQ(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult, reason string, err error, fields ...kvp.Field) {
	fields = append(fields, kvp.String("origin", reason))
	logger.WithError(err).Error("error on emission", fields...)
	_ = h.AddToDeadLetterQueue(ctx, logger, rr.Payload, stats.Tags{"origin": reason})
	h.TrackEmissionError(reason)
}

func (h *EmissionHandler) TrackEmissionError(reason string) {
	h.statter.Counter("emission-error", stats.Tags{"origin": reason}, int64(1))
	h.statter.Counter("emission-handler", stats.Tags{"success": "false"}, int64(1))
}

func (h *EmissionHandler) rejectItemsByProduct(items []*models.Item, product string) []*models.Item {
	var filtered []*models.Item
	for _, item := range items {
		if item.GetProduct() != product {
			filtered = append(filtered, item)
		}
	}
	return filtered
}
func (h *EmissionHandler) rejectDiscountItemsByProduct(items []*models.DiscountItem, product string) []*models.DiscountItem {
	var filtered []*models.DiscountItem
	for _, item := range items {
		if item.GetProduct() != product {
			filtered = append(filtered, item)
		}
	}
	return filtered
}

func (h *EmissionHandler) ValidateUsageItems(ctx context.Context, logger log.Logger, customer *models.Customer, items []*models.Item) ([]*models.Item, error) {
	var validItems []*models.Item

	enterpriseInfo, err := h.customerEngine.GetEnterpriseInfoFromItem(ctx, logger, items[0])
	if err != nil {
		logger.Error("failed to retrieve enterprise info from item", kvp.String("error", err.Error()))
		return nil, err
	}

	for _, item := range items {
		// Skip emitting high watermark items for customers offboarded from the product.
		if item.IsHighWatermarkEvent() && !enterpriseInfo.IsProductEnabled(item.GetProduct()) {
			h.TrackEmissionError("customer.usageEmissionDisabled")
			logger.Error("product is not configured to emit to azure", kvp.String("product", item.GetProduct()), kvp.String("customerID", enterpriseInfo.EnterpriseCustomerId), kvp.String("costCenterUUID", enterpriseInfo.CostCenterUUID))
			continue // Skip this item due to disabled product
		}

		// Skip free SKUs that should not be charged to Zuora.
		if item.Amounts.ToDecimal().BilledAmount == 0 {
			h.statter.Counter("zuora-emission-free-usage", stats.Tags{"product-sku": item.GetSku()}, int64(1))
			logger.Debug("item is free pricing", kvp.String("sku", item.GetSku()))
			continue // Skip free items
		}

		// Adjust quantity for watermark items with per-hour unit charge.
		if item.GetMeterType() == models.PricingMeterPerHourUnitCharge {
			daysInMonth := int64(item.UsageAt.BillableDaysInMonth()) * nano.NanoDivisor
			hoursInDay := int64(24) * nano.NanoDivisor

			// Convert quantity from GB/h to GB/m.
			entityQuantity := nano.NewFromInt(item.Quantity).Div(nano.NewFromInt(hoursInDay)).Div(nano.NewFromInt(daysInMonth))
			item.Quantity = entityQuantity.Int64()
			item.Amounts.Quantity = entityQuantity.Int64()
		}

		// Add the item to the list of valid items.
		validItems = append(validItems, item)

	}

	return validItems, nil
}

func (h *EmissionHandler) includeLateDiscountItems(ctx context.Context, logger log.Logger, customer *models.Customer, discountItems []*models.DiscountItem, emissionDateTime models.UsageTime) ([]*models.DiscountItem, error) {

	// Generate the partition key for the late discounts from the previous day
	partitionDetailsLateUsage, err := models.GetPartitionDetailForLateDisount(emissionDateTime, customer.GetCustomerId())
	if err != nil {
		logger.WithError(err).Error("error creating late usage partition detail")
		return nil, err
	}

	// Retrieve late discount items from the previous day's partition
	lateDiscountItems, err := h.usageEngine.GetLateDiscountLineItems(ctx, logger, partitionDetailsLateUsage)
	if err != nil {
		logger.WithError(err).Error("failed to retrieve late discount line items")
		return nil, err
	}

	// Append the late discount items to the existing discount items
	discountItems = append(discountItems, lateDiscountItems...)

	return discountItems, nil

}
func (h *EmissionHandler) getEnabledCustomerIDs(customersWithDailyEmissionEnabled string) []string {
	// Acquire read lock
	cacheEmissionRWMutex.RLock()
	if len(cachedEnabledCustomerIDs) > 0 {
		defer cacheEmissionRWMutex.RUnlock()
		return cachedEnabledCustomerIDs
	}
	cacheEmissionRWMutex.RUnlock()

	// Acquire write lock
	cacheEmissionRWMutex.Lock()
	defer cacheEmissionRWMutex.Unlock()

	// Double-check to prevent race condition
	once.Do(func() {
		if len(cachedEnabledCustomerIDs) == 0 {
			cachedEnabledCustomerIDs = strings.Split(customersWithDailyEmissionEnabled, ",")
		}
	})

	return cachedEnabledCustomerIDs
}
