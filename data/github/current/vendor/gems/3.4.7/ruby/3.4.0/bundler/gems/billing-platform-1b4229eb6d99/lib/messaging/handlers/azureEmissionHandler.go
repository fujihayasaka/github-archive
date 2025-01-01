package handlers

import (
	"context"
	"encoding/json"
	"strconv"
	"time"

	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/azurecommerce"
	"github.com/github/billing-platform/lib/data"
	"github.com/github/billing-platform/lib/engines"
	stats "github.com/github/go-stats"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
)

type AzureEmissionHandler struct {
	*Handler
	ac                  *azurecommerce.AzureCommerce
	customerEngine      engines.CustomerEngineInterface
	costCenterEngine    engines.CostCenterEngineInterface
	azureEmissionEngine engines.AzureEmissionEngineInterface
	usageEngine         engines.UsageEngineInterface
	dataService         *data.DataService
	discountEngine      engines.DiscountEngineInterface
}

func NewAzureEmissionHandler(
	params *HandlerParams,
	ac *azurecommerce.AzureCommerce,
	customerEngine engines.CustomerEngineInterface,
	costCenterEngine engines.CostCenterEngineInterface,
	azureEmissionEngine engines.AzureEmissionEngineInterface,
	usageEngine engines.UsageEngineInterface,
	dataService *data.DataService,
	discountEngine engines.DiscountEngineInterface,
) *AzureEmissionHandler {
	return &AzureEmissionHandler{
		Handler:             NewHandler(params, models.WorkerTypeAzureEmission),
		ac:                  ac,
		customerEngine:      customerEngine,
		costCenterEngine:    costCenterEngine,
		azureEmissionEngine: azureEmissionEngine,
		usageEngine:         usageEngine,
		dataService:         dataService,
		discountEngine:      discountEngine,
	}
}

func (h *AzureEmissionHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	start := time.Now()
	defer func() {
		duration := time.Since(start)
		h.statter.Timing("azure-emission-handler", stats.Tags{}, duration)
	}()

	logger.Debug("unmarshalling enveloped message", kvp.String("payload", string(rr.Payload)))

	var item *models.Item
	if err := json.Unmarshal(rr.Payload, &item); err != nil {
		h.TrackEmissionErrorAndAddToDLQ(ctx, logger, rr, "unmarshal_error", errors.Wrap(err, "failed to unmarshal enveloped message"))
		return nil
	}

	enterpriseInfo, err := h.customerEngine.GetEnterpriseInfoFromItem(ctx, logger, item)
	if err != nil {
		if item.IsHighWatermarkEvent() {
			// If the customer has been deleted for a high watermark event, we should not emit to Azure or add to the DLQ.
			// This is a known issue for high watermark items, which write forward to the azure emission partition when the event initially is ingested.
			h.TrackEmissionError("customer.enterpriseDeletedForHighWatermarkItem")
			logger.Error("high watermark item is for a nonexistent enterprise")
		} else {
			h.TrackEmissionErrorAndAddToDLQ(ctx, logger, rr, "customer.info", err, kvp.String("customerID", item.GetCustomerId()))
		}
		return nil
	}

	// Don't emit high watermark usages for customers that are offboarded from product.
	if item.IsHighWatermarkEvent() && !enterpriseInfo.IsProductEnabled(item.GetProduct()) {
		// Don't emit to DLQ here as we expect this to happen for customers that are not configured to emit to Azure.
		h.TrackEmissionError("customer.usageEmissionDisabled")
		logger.Error("product is not configured to emit to azure", kvp.String("product", item.GetProduct()), kvp.String("customerID", enterpriseInfo.EnterpriseCustomerId), kvp.String("costCenterUUID", enterpriseInfo.CostCenterUUID))
		return nil
	}

	// Free SKUs should not be charged to Azure.
	if item.Amounts.ToDecimal().BilledAmount == 0 {
		h.statter.Counter("azure-emission-free-usage", stats.Tags{"product-sku": item.GetSku()}, int64(1))
		logger.Debug("item is free pricing", kvp.String("sku", item.GetSku()))
		return nil
	}

	// Skip SKUs without an Azure meter id
	if item.GetAzureMeterId() == "" {
		h.statter.Counter("azure-emission-no-meter-id", stats.Tags{"product-sku": item.GetSku()}, int64(1))
		logger.Debug("item pricing does not have an Azure meter id", kvp.String("sku", item.GetSku()))
		return nil
	}

	// For watermark items, we need to spread the current quantity across the number of days in the month.
	if item.GetMeterType() == models.PricingMeterPerHourUnitCharge {
		daysInMonth := int64(item.UsageAt.BillableDaysInMonth()) * nano.NanoDivisor
		hoursInDay := int64(24) * nano.NanoDivisor
		// item.Quantity is in GB/h here. We need to convert it to GB/d (divide by 24) and then GB/m (divide by daysInMonth)
		// as the azure meter for watermark items is in GB/m.
		// The price on this quantity might be slightly higher than the calculated price in the UI using our internal pricing engine
		// due to our price being calculated using the normalized hours in a month (730).
		entityQuantity := nano.NewFromInt(item.Quantity).Div(nano.NewFromInt(hoursInDay)).Div(nano.NewFromInt(daysInMonth))

		item.Quantity = entityQuantity.Int64()
		item.Amounts.Quantity = entityQuantity.Int64()
	}

	return h.EmitToAzure(ctx, logger, rr, item, enterpriseInfo)
}

func (h *AzureEmissionHandler) EmitToAzure(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult, item *models.Item, enterpriseInfo *models.EnterpriseInfo) error {
	// ensure the item has not yet been emitted
	hasItemBeenEmitted, err := h.HasItemBeenEmitted(ctx, logger, item)
	if err != nil {
		h.TrackEmissionErrorAndAddToDLQ(
			ctx,
			logger,
			rr,
			"customer.getAzureEmissionRecord",
			errors.Wrap(err, "error querying azure emission record"),
			kvp.String("SKU", item.GetSku()),
			kvp.String("customerID", enterpriseInfo.EnterpriseCustomerId),
			kvp.String("costCenterUUID", enterpriseInfo.CostCenterUUID),
		)
		return nil
	} else if hasItemBeenEmitted {
		h.statter.Counter("azure-emission-skipped", stats.Tags{"sku": item.GetSku()}, int64(1))
		logger.Info("azure emission skipped", kvp.String("sku", item.GetSku()), kvp.String("customerId", item.GetCustomerId()))
		return nil
	}

	discountQuantity, err := h.discountEngine.GetDailyDiscountQuantity(ctx, logger, item)
	if err != nil {
		h.TrackEmissionErrorAndAddToDLQ(
			ctx,
			logger,
			rr,
			"customer.discounts",
			errors.Wrap(err, "error getting discount quantity"),
			kvp.String("customerID", enterpriseInfo.EnterpriseCustomerId),
			kvp.String("costCenterUUID", enterpriseInfo.CostCenterUUID),
		)
		return nil
	}

	var azureEmission *models.AzureEmission
	if item.IsCostCenterProxy() {
		azureEmission, err = h.ac.EmitLineItem(ctx, h.statter, h.cfg, item, enterpriseInfo.AzureAccountId, enterpriseInfo.CostCenterUUID, discountQuantity)
	} else {
		azureEmission, err = h.ac.EmitLineItem(ctx, h.statter, h.cfg, item, enterpriseInfo.AzureAccountId, enterpriseInfo.EnterpriseCustomerId, discountQuantity)
	}

	logger.Info("Discount details for azure emission", kvp.Float64("quantity", item.Amounts.ToDecimal().Quantity), kvp.Float64("discountQuantity", discountQuantity), kvp.String("sku", item.GetSku()), kvp.String("customerID", item.GetCustomerId()))

	if err != nil {
		h.TrackEmissionErrorAndAddToDLQ(
			ctx,
			logger,
			rr,
			"customer.azureEmission",
			errors.Wrap(err, "error emitting to azure"),
			kvp.String("customerID", enterpriseInfo.EnterpriseCustomerId),
			kvp.String("costCenterUUID", enterpriseInfo.CostCenterUUID),
		)
		return nil
	}

	// Save azure emission record to the database
	_, upsertErr := h.azureEmissionEngine.UpsertAzureEmission(ctx, logger, azureEmission)
	if upsertErr != nil {
		h.TrackEmissionErrorAndAddToDLQ(
			ctx,
			logger,
			rr,
			"customer.saveEmissionRecord",
			errors.Wrap(upsertErr, "error saving azure emission record"),
			kvp.String("customerID", enterpriseInfo.EnterpriseCustomerId),
			kvp.String("costCenterUUID", enterpriseInfo.CostCenterUUID),
		)
		return nil
	}

	if azureEmission.Status == models.AzureEmissionFailed {
		h.TrackEmissionErrorAndAddToDLQ(
			ctx,
			logger,
			rr,
			"customer.azureEmissionFailed",
			errors.New(azureEmission.ErrorMessage),
			kvp.String("customerID", enterpriseInfo.EnterpriseCustomerId),
			kvp.String("costCenterUUID", enterpriseInfo.CostCenterUUID),
		)
		return nil
	}

	// Use false for the dry run value.
	h.dataService.PublishAzureInvoiceMessage(ctx, logger, enterpriseInfo, item, azureEmission, false)

	h.statter.Counter(
		"azure-emission-handler",
		stats.Tags{
			"success":    strconv.FormatBool(azureEmission.Status != models.AzureEmissionFailed),
			"status":     azureEmission.Status.GetStatusString(),
			"costCenter": strconv.FormatBool(item.IsCostCenterProxy()),
		},
		int64(1),
	)

	return nil
}

func (h *AzureEmissionHandler) HasItemBeenEmitted(ctx context.Context, logger log.Logger, item *models.Item) (bool, error) {
	azureEmissionPartitionDetail := &models.AzureEmissionPartitionDetail{
		CustomerId: item.GetCustomerId(),
		Sku:        item.GetSku(),
		Year:       int64(item.UsageAt.Year()),
		Month:      int64(item.UsageAt.Month()),
		Day:        int64(item.UsageAt.Day()),
	}

	azureEmissionRecord, err := h.azureEmissionEngine.GetAzureEmission(ctx, logger, azureEmissionPartitionDetail)
	if err != nil {
		return false, err
	} else if azureEmissionRecord != nil && azureEmissionRecord.Status == models.AzureEmissionCompleted {
		return true, nil
	}

	return false, nil
}

func (h *AzureEmissionHandler) TrackEmissionErrorAndAddToDLQ(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult, reason string, err error, fields ...kvp.Field) {
	fields = append(fields, kvp.String("origin", reason))
	logger.WithError(err).Error("error on azure emission", fields...)
	_ = h.AddToDeadLetterQueue(ctx, logger, rr.Payload, stats.Tags{"origin": reason})
	h.TrackEmissionError(reason)
}

func (h *AzureEmissionHandler) TrackEmissionError(reason string) {
	h.statter.Counter("azure-emission-error", stats.Tags{"origin": reason}, int64(1))
	h.statter.Counter("azure-emission-handler", stats.Tags{"success": "false"}, int64(1))
}
