package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"

	stats "github.com/github/go-stats"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydro_schemas_billingplatform_v1_entities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/zuora"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
)

type ZuoraBatchEmissionHandler struct {
	*Handler
	zuoraEngine      engines.ZuoraEngineInterface
	hydroPublisher   interfaces.HydroPublisher
	productEngine    engines.ProductEngineInterface
	costCenterEngine engines.CostCenterEngineInterface
	discountEngine   engines.DiscountEngineInterface
	customerEngine   engines.CustomerEngineInterface
}

func NewZuoraBatchEmissionHandler(
	params *HandlerParams,
	zuoraEngine engines.ZuoraEngineInterface,
	hydroPublisher interfaces.HydroPublisher,
	productEngine engines.ProductEngineInterface,
	costCenterEngine engines.CostCenterEngineInterface,
	discountEngine engines.DiscountEngineInterface,
	customerEngine engines.CustomerEngineInterface,
) *ZuoraBatchEmissionHandler {
	return &ZuoraBatchEmissionHandler{
		Handler:          NewHandler(params, models.WorkerTypeZuoraBatchEmissionHandler),
		zuoraEngine:      zuoraEngine,
		hydroPublisher:   hydroPublisher,
		productEngine:    productEngine,
		costCenterEngine: costCenterEngine,
		discountEngine:   discountEngine,
		customerEngine:   customerEngine,
	}
}

func (h *ZuoraBatchEmissionHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	logger.Debug("Processing message in", kvp.String("queue", h.queueName))
	logger.Debug("unmarshalling enveloped message", kvp.String("payload", string(rr.Payload)))

	start := time.Now()
	defer func() {
		duration := time.Since(start)
		h.statter.Timing("zuora-batch-emission-handler.processing-time", stats.Tags{}, duration)
	}()

	logger.Debug("unmarshalling enveloped message", kvp.String("payload", string(rr.Payload)))

	var items *models.ZuoraBatchEmissionPayload
	if err := json.Unmarshal(rr.Payload, &items); err != nil {
		h.TrackEmissionErrorAndAddToDLQ(ctx, logger, rr, "unmarshal_error", errors.Wrap(err, "failed to unmarshal enveloped message"))
		return nil
	}

	if err := h.processBatchesToZuora(ctx, logger, items); err != nil {
		h.TrackEmissionErrorAndAddToDLQ(ctx, logger, rr, "zuora_batch_emission_error", errors.Wrap(err, "failed to process zuora batch emission"))
	}

	return nil
}

func (h *ZuoraBatchEmissionHandler) processBatchesToZuora(ctx context.Context, logger log.Logger, items *models.ZuoraBatchEmissionPayload) error {
	start := time.Now()
	defer func() {
		duration := time.Since(start)
		h.statter.Timing("zuora_batch_emission_handler", stats.Tags{}, duration)
	}()

	logger = logger.WithFields(
		kvp.String("Batch Number", strconv.Itoa(items.BatchNumber)),
		kvp.String("Year", strconv.Itoa(items.Year)),
		kvp.String("Month", strconv.Itoa(items.Month)),
		kvp.String("Day", strconv.Itoa(items.Day)),
	)

	logger.Info("Starting Zuora batch emission processing")

	batchStatusPartitionDetail := models.GetPartitionDetailForZuoraEmissionBatchStatus(items.Year, items.Month, items.Day)
	batchStatusRecords, err := h.zuoraEngine.GetZuoraEmissionBatchStatus(ctx, logger, batchStatusPartitionDetail)
	if err != nil {
		logger.WithError(err).Error("Failed to retreive batch status records")
		return errors.Wrap(err, "failed to retreive batch status records")
	}

	var currentStatusRecord *models.ZuoraEmissionBatchStatus
	for _, record := range batchStatusRecords {
		if record.BatchNumber == items.BatchNumber &&
			record.Status != models.BatchStatusFailed &&
			record.Status != models.BatchStatusSubmitted {
			currentStatusRecord = record
			break
		}
	}

	if currentStatusRecord == nil {
		logger.Error("No batch status record found in 'building' or 'ready to submit' state",
			kvp.Int("batchNumber", items.BatchNumber))
		return errors.New("no batch status record found in 'building' or 'ready to submit' state")
	}

	batchPartitionDetail := models.NewZuoraEmissionBatchPartitionDetail(items.Year, items.Month, items.Day, items.BatchNumber, "")
	batchRecords, err := h.zuoraEngine.GetZuoraEmissionBatch(ctx, logger, batchPartitionDetail)
	if err != nil {
		logger.WithError(err).Error("Failed to retrieve batch records")
		return errors.Wrap(err, "failed to retrieve batch records")
	}

	var zuoraUsageRecords []zuora.UploadUsageRecord
	for _, batchRecord := range batchRecords {
		zuoraUsageRecords = append(zuoraUsageRecords, batchRecord.UploadUsageRecords...)
	}

	if err = h.zuoraEngine.EmitDailyBatchToZuora(ctx, logger, zuoraUsageRecords); err != nil {
		logger.WithError(err).Error("Failed to emit batch to Zuora")

		currentStatusRecord.Status = models.BatchStatusFailed
		_, err = h.zuoraEngine.UpsertZuoraEmissionBatchStatus(ctx, logger, currentStatusRecord)
		if err != nil {
			logger.WithError(err).Error("Failed to upsert batch status records")
			return errors.Wrap(err, "failed to upsert batch status records")
		}
		return err
	}

	currentStatusRecord.Status = models.BatchStatusSubmitted
	if _, err = h.zuoraEngine.UpsertZuoraEmissionBatchStatus(ctx, logger, currentStatusRecord); err != nil {
		logger.WithError(err).Error("Failed to update batch status to 'submitted'")
		return errors.Wrap(err, "failed to update batch status to 'submitted'")

	}

	err = h.emitDailyEmissionToHydro(ctx, logger, items, batchRecords)
	if err != nil {
		logger.WithError(err).Error("Failed to process daily emission to hydro")
		return errors.Wrap(err, "failed to process daily emission to hydro")
	}

	logger.Info("Successfully completed Zuora batch emission processing")
	return nil
}

func (h *ZuoraBatchEmissionHandler) emitDailyEmissionToHydro(ctx context.Context, logger log.Logger, items *models.ZuoraBatchEmissionPayload, emissionBatch []*models.ZuoraEmissionBatch) error {

	for _, batchRecord := range emissionBatch {

		customerID := strings.TrimPrefix(batchRecord.Key.Id, "customer:")
		emissionRecords, err := h.zuoraEngine.GetZuoraEmissions(ctx, logger, customerID, int64(items.Year), int64(items.Month), int64(items.Day))
		if err != nil || len(emissionRecords) == 0 {
			logger.WithError(err).WithFields(
				kvp.String("customerID", customerID),
				kvp.Int("year", items.Year),
				kvp.Int("month", items.Month),
				kvp.Int("day", items.Day),
			).Error("Failed to get emission records for customer")
			return errors.Wrapf(err, "failed to get emission records for customer %s", customerID)
		}

		invoiceHydroSchema := h.generateBatchHydroMessage(ctx, logger, customerID, items, emissionRecords[0])

		if err = h.hydroPublisher.Publish(invoiceHydroSchema); err != nil {
			logger.WithError(err).Error("Failed to publish hydro message")
			return errors.Wrap(err, "failed to publish hydro message")
		} else {
			logger.Info("Successfully published hydro message")
		}

	}
	return nil
}

func (h *ZuoraBatchEmissionHandler) generateBatchHydroMessage(ctx context.Context, logger log.Logger, customerId string, item *models.ZuoraBatchEmissionPayload, emission *models.Emission) *hydroSchema.Invoice {
	now := timestamppb.New(time.Now().UTC())
	// hardcode to the date of the emission
	usageTime := models.NewUsageTime().WithYear(int64(item.Year)).
		WithMonthInt(int64(item.Month)).WithDay(item.Day).WithHour(0)

	customer, err := h.customerEngine.Get(ctx, logger, customerId, false)
	if err != nil {
		logger.WithError(err).Error("failed to find customer")
		return nil
	}

	var skus []*hydro_schemas_billingplatform_v1_entities.SkuInvoice

	for _, productTotal := range emission.ProductTotals {
		var billingTargetChargeId string
		product, _ := h.productEngine.Get(ctx, logger, productTotal.Product, false)
		if product != nil {
			billingTargetChargeId = product.ZuoraUsageIdentifier
		}

		for _, skuTotal := range productTotal.SkuTotals {
			var discountQuantity float64
			discountTotals, _, err := h.discountEngine.GetDiscountTotal(ctx, logger, &models.UsagePartitionDetail{
				// Use the invoice customer ID here in case it is a cost center
				UsageEntityId: customer.GetCustomerId(),
				Product:       productTotal.Product,
				Sku:           skuTotal.Sku,
				UsageTime:     usageTime,
				ActiveType:    models.Monthly,
			})
			if err != nil {
				logger.WithError(err).Error("failed to retrieve discount total")
				h.statter.Counter("customer-invoice-discount-error", stats.Tags{}, int64(1))
				discountQuantity = 0

			} else {
				discountQuantity = discountTotals.ToDecimal().Quantity
			}

			skuInvoiceSchema := &hydro_schemas_billingplatform_v1_entities.SkuInvoice{
				Name:                  skuTotal.Sku,
				Product:               productTotal.Product,
				GrossQuantity:         skuTotal.UsageTotal.Quantity,
				DiscountQuantity:      discountQuantity,
				NetQuantity:           skuTotal.UsageTotal.Quantity - discountQuantity,
				GrossBilledAmount:     skuTotal.UsageTotal.Gross,
				DiscountAmount:        skuTotal.UsageTotal.Discount,
				NetBilledAmount:       skuTotal.UsageTotal.Net,
				BillingTargetChargeId: billingTargetChargeId,
			}

			if len(skuTotal.BillingItems) > 0 {
				skuInvoiceSchema.UnitType = skuTotal.BillingItems[0].GetUnitType().String()
			}

			skus = append(skus, skuInvoiceSchema)
		}
	}

	invoiceHydroSchema := hydroSchema.Invoice{
		InvoiceId:            emission.Key.Id,
		CustomerId:           customer.EnterpriseCustomerId,
		Skus:                 skus,
		GrossBilledAmount:    emission.UsageTotal.Gross,
		DiscountAmount:       emission.UsageTotal.Discount,
		NetAmountDue:         emission.UsageTotal.Net,
		PaymentProcessorId:   customer.ZuoraAccountNumber,
		UsageAt:              timestamppb.New(usageTime.Time),
		GeneratedByBillingAt: now,
		Target:               customer.GetHydroBillingTarget(),
		InvoiceYear:          int64(item.Year),
		InvoiceMonth:         int64(item.Month),
		InvoiceDay:           int64(item.Day),
		BillingTargetId:      customer.ZuoraAccountNumber,
	}

	if customer.IsCostCenterProxy {
		costCenterKey := &models.CostCenterKey{
			Key: &models.Key{
				PartitionKey: fmt.Sprintf("customer:%s:costCenters", customer.EnterpriseCustomerId),
				Id:           customer.CostCenterUUID,
			},
		}

		costCenter, err := h.costCenterEngine.Get(ctx, logger, costCenterKey)
		if err != nil {
			logger.WithError(err).Error("failed to find cost center")
		} else {
			costCenterEntity := hydro_schemas_billingplatform_v1_entities.CostCenter{
				Uuid: costCenter.UUID,
				Name: costCenter.Name,
			}

			invoiceHydroSchema.CostCenter = &costCenterEntity
		}
	}

	return &invoiceHydroSchema
}

func (h *ZuoraBatchEmissionHandler) TrackEmissionErrorAndAddToDLQ(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult, reason string, err error, fields ...kvp.Field) {
	fields = append(fields, kvp.String("origin", reason))
	logger.WithError(err).Error("error on zuora emission batch", fields...)
	_ = h.AddToDeadLetterQueue(ctx, logger, rr.Payload, stats.Tags{"origin": reason})
	h.TrackEmissionError(reason)
}

func (h *ZuoraBatchEmissionHandler) TrackEmissionError(reason string) {
	h.statter.Counter("zuora-emission-batch-error", stats.Tags{"origin": reason}, int64(1))
	h.statter.Counter("zuora-emission-batch-handler", stats.Tags{"success": "false"}, int64(1))
}
