package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"sync"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydroSchemaEntities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/messaging"
	stats "github.com/github/go-stats"
	schemas "github.com/github/hydro-client-go/v5/generated/hydro/schemas/hydro/v1"
	protobuf "github.com/golang/protobuf/proto" //nolint:staticcheck
	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

type WatermarkHandler struct {
	*Handler
	customerEngine *engines.CustomerEngine
	usageEngine    *engines.UsageEngine
	watermarkJob   *models.WatermarkJob
}

func NewWatermarkHandler(
	params *HandlerParams,
	customerEngine *engines.CustomerEngine,
	usageEngine *engines.UsageEngine,
) *WatermarkHandler {
	return &WatermarkHandler{
		Handler:        NewHandler(params, models.WorkerTypeWatermarkHandler),
		customerEngine: customerEngine,
		usageEngine:    usageEngine,
	}
}

func (h *WatermarkHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	ctx, sp := h.tracer.Start(ctx, "WatermarkHandler.ProcessMessage")
	defer sp.End()
	if success := h.validateHandlerDetails(ctx, logger, rr); !success {
		return nil
	}

	ctx, gwsp := h.tracer.Start(ctx, "WatermarkHandler.ProcessMessage.GetWatermarkEventRollups")
	rollups, err := h.usageEngine.GetWatermarkEventRollups(ctx, logger, h.watermarkJob.ActiveCustomer.Id, h.watermarkJob.PartitionDetail.Sku)
	gwsp.End()

	if err != nil {
		h.TrackEmissionError(ctx, logger, rr, "customer.rollups", errors.Wrap(err, "Failed to retrieve rollups for active event customer"), true, kvp.String("customerID", h.watermarkJob.ActiveCustomer.Id))
		return nil
	}
	if len(rollups) == 0 {
		// active:events customers aren't cleaned up when they become inactive,
		// may be cases where we can't find rollups for them.
		h.TrackEmissionError(ctx, logger, rr, "customer.rollups", errors.New("No rollups found for active event customer"), false)
		return nil
	}

	firstRollup := rollups[0]

	if !firstRollup.IsEnabledForEmission() {
		h.TrackEmissionError(ctx, logger, rr, "rollup.is_enabled_for_emission", errors.New("Sku disabled for watermark processing"), false, kvp.String("sku", firstRollup.GetSku()))
		return nil
	}

	if !h.IsRunInCurrentHour() {
		rollups = h.filterFutureRollups(rollups)
	}
	ctx, rsp := h.tracer.Start(ctx, "WatermarkHandler.ProcessMessage.rollupsToMap")
	quantityByEntity := h.rollupsToMap(rollups)
	rsp.End()

	ctx, gsp := h.tracer.Start(ctx, "WatermarkHandler.ProcessMessage.generateLineItems")
	lineItems := h.generateLineItems(quantityByEntity, firstRollup.Pricing, firstRollup.AppliedCostPerQuantity)
	gsp.End()

	ctx, esp := h.tracer.Start(ctx, "WatermarkHandler.ProcessMessage.emitLineItems")
	err = h.emitLineItems(ctx, logger, rr, lineItems, h.watermarkJob.ActiveCustomer.Id)
	esp.End()

	if err != nil {
		return err
	}

	return nil
}

func (h *WatermarkHandler) validateHandlerDetails(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) bool {
	if err := json.Unmarshal(rr.Payload, &h.watermarkJob); err != nil {
		h.TrackEmissionError(ctx, logger, rr, "unmarshal.err", errors.New("Invalid json"), true)
		return false
	}

	if h.watermarkJob.ActiveCustomer == nil || h.watermarkJob.ActiveCustomer.Id == "" {
		h.TrackEmissionError(ctx, logger, rr, "customer.err", errors.New("Empty customer id"), true)
		return false
	}

	if h.watermarkJob.PartitionDetail == nil {
		h.TrackEmissionError(ctx, logger, rr, "partitionDetail.err", errors.New("Missing partition detail"), true)
		return false
	}

	if h.watermarkJob.JobRun == nil {
		h.TrackEmissionError(ctx, logger, rr, "jobRun.err", errors.New("Missing job run"), true)
		return false
	}

	return true
}

func (h *WatermarkHandler) IsRunInCurrentHour() bool {
	jobRunUsageTime := h.watermarkJob.JobRun.ToUsageTime()
	currentTime := models.NewUsageTime()

	return currentTime.Hour() == jobRunUsageTime.Hour() &&
		currentTime.Day() == jobRunUsageTime.Day() &&
		currentTime.Month() == jobRunUsageTime.Month() &&
		currentTime.Year() == jobRunUsageTime.Year()
}

// All rollups for a given customer are returned from the query. We need to filter out
// rollups from hours in the future of the current job run time. This is applicable for
// when we replay events from the DLQ to ensure we don't aggregate  incorrect quantities.
func (h *WatermarkHandler) filterFutureRollups(rollups []*models.Item) []*models.Item {
	var filteredRollups []*models.Item
	jobRunUsageTime := h.watermarkJob.JobRun.ToUsageTime()

	for _, rollup := range rollups {
		if rollup.UsageAt.StartOfHour().Before(jobRunUsageTime.StartOfHour()) || rollup.UsageAt.StartOfHour().Equal(jobRunUsageTime.StartOfHour()) {
			filteredRollups = append(filteredRollups, rollup)
		}
	}
	return filteredRollups
}

func (h *WatermarkHandler) rollupsToMap(rollups []*models.Item) *sync.Map {
	var quantityByEntity sync.Map

	// TODO: Unsure if this var is actually used anywhere in the loop
	customerBilledAmount := nano.NewFromInt(0)

	for _, rollup := range rollups {
		rollupTime := rollup.UsageAt
		mapKey := fmt.Sprintf("%s:%d:%d", rollup.EntityDetail.CustomerId, rollup.EntityDetail.OrganizationId, rollup.EntityDetail.RepositoryId)
		var entityQuantity *nano.Nano
		jobRunDay := h.watermarkJob.JobRun.ToUsageTime()

		sameDayRollup := rollupTime.StartOfDay() == jobRunDay.StartOfDay()
		// When it's 00:00, we need to look at the FractionalQuantity for the previous day
		startOfNextDay := jobRunDay.Hour() == 0 && jobRunDay.StartOfDay().Sub(rollupTime.StartOfDay()) == 24*time.Hour

		if sameDayRollup || startOfNextDay {
			entityQuantity = nano.NewFromInt(rollup.FractionalQuantity)
		} else {
			entityQuantity = nano.NewFromInt(rollup.Quantity)
		}

		entityQuantity = entityQuantity.Div(nano.NewFromInt(models.ToWholeAmount[int64](24)))

		// TODO: This block doesn't seem to be used anywhere, but it's not clear why
		price := nano.NewFromInt(rollup.GetPrice())
		effectiveBilledAmount := price.Mul(entityQuantity)
		customerBilledAmount = customerBilledAmount.Add(effectiveBilledAmount)

		val, _ := quantityByEntity.LoadOrStore(mapKey, nano.NewFromInt(0))
		finalVal := entityQuantity.Add(val.(*nano.Nano))
		quantityByEntity.Store(mapKey, finalVal)
	}

	return &quantityByEntity
}

func (h *WatermarkHandler) generateLineItems(quantityByEntity *sync.Map, pricing *models.Pricing, appliedCostPerQuantity int64) []*models.Item {
	var lineItems []*models.Item

	quantityByEntity.Range(func(k, v interface{}) bool {
		entityQuantity := v.(*nano.Nano)
		entityInfo := strings.Split(k.(string), ":")
		orgId, _ := strconv.ParseInt(entityInfo[1], 10, 64)
		repoId, _ := strconv.ParseInt(entityInfo[2], 10, 64)
		entityDetail := &models.EntityDetail{
			CustomerId:     entityInfo[0],
			OrganizationId: orgId,
			RepositoryId:   repoId,
		}

		lineItems = append(lineItems, &models.Item{
			Key:     *h.watermarkJob.ActiveCustomer,
			Pricing: pricing,
			UsageAt: *models.UTCNow(),
			Amounts: &models.Amounts{
				Quantity:               entityQuantity.Int64(),
				AppliedCostPerQuantity: appliedCostPerQuantity,
			},
			EntityDetail: entityDetail,
		})

		return true
	})

	h.statter.Counter("watermark_handler.count_customer_usage", stats.Tags{}, int64(len(lineItems)))

	return lineItems
}

func (h *WatermarkHandler) emitLineItems(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult, lineItems []*models.Item, customerId string) error {
	jobRun := h.watermarkJob.JobRun
	for _, usage := range lineItems {
		customerIdAsInt, err := strconv.ParseInt(usage.EntityDetail.CustomerId, 10, 64)
		if err != nil {
			h.TrackEmissionError(ctx, logger, rr, "customer.err", err, true, kvp.String("customerID", customerId))
			return errors.Wrap(err, "Failed to parse customer id")
		}

		if usage.Amounts.Quantity <= 0 {
			h.statter.Counter("watermark_handler.negative_or_zero_quantity", stats.Tags{"product_sku": h.watermarkJob.PartitionDetail.Sku}, int64(1))
			continue
		}

		if usage.Amounts.BilledAmount < 0 {
			h.statter.Counter("watermark_handler.negative_or_zero_amount", stats.Tags{"product_sku": h.watermarkJob.PartitionDetail.Sku}, int64(1))
			continue
		}

		// Create the lineItem for the Hour being processed
		usageAt := jobRun.ToUsageTime().StartOfHour()
		asHydroMessage := &hydroSchema.Usage{
			Sku:       usage.GetSku(),
			Quantity:  models.ToDecimalAmount[int64](usage.Quantity),
			SourceUri: models.InternallyProcessedEvent,
			UsageAt:   timestamppb.New(usageAt),
			Entity: &hydroSchemaEntities.EntityDetail{
				CustomerId:     customerIdAsInt,
				OrganizationId: usage.EntityDetail.OrganizationId,
				RepoId:         usage.EntityDetail.RepositoryId,
				ActorId:        usage.EntityDetail.ActorId,
			},
			UsageUuid: fmt.Sprintf("%d:%s:%d:%d:%d:%d:%d:%d", customerIdAsInt, usage.GetSku(), usage.EntityDetail.OrganizationId, usage.EntityDetail.RepositoryId, jobRun.Year, jobRun.Month, jobRun.Day, jobRun.Hour),
		}

		// Marshal the usage into JSON that matches hydroSchema.Usage
		usageAsBytes, err := protobuf.Marshal(asHydroMessage)
		if err != nil {
			logger.WithError(err).Error("Failed to marshal usage")
			return errors.Wrap(err, "Failed to marshal usage")
		}

		envelope := schemas.Envelope{
			Message: usageAsBytes,
		}
		envelopeBytes, err := protobuf.Marshal(&envelope)
		if err != nil {
			logger.WithError(err).Error("Failed to marshal envelope")
			return errors.Wrap(err, "Failed to marshal envelope")
		}

		// Send line items back to the usage ingestion handler
		job := aqueduct.Job{
			App:     h.cfg.AqueductApplication(),
			Queue:   messaging.GetQueueName(models.WorkerTypeUsageIngestion, h.cfg.OverrideQueuePrefix),
			Payload: envelopeBytes,
		}
		_, err = h.aqueductClient.Send(ctx, job, messaging.MessageSenderOptions()...)

		if err != nil {
			l := logger.WithFields(
				kvp.String("aqueduct.job.app", job.App),
				kvp.String("aqueduct.job.queue", job.Queue),
				kvp.String("aqueduct.job.payload", string(usageAsBytes)),
			)
			l.WithError(err).Error("error submitting watermark for usage ingestion")
			continue
		}

		h.statter.Counter("watermark_handler.send_usage", stats.Tags{}, int64(1))
	}

	return nil
}

func (h *WatermarkHandler) TrackEmissionError(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult, reason string, err error, addToDlq bool, fields ...kvp.Field) {
	logger.WithError(err).Error("error in watermark handler", fields...)
	h.statter.Counter("watermark_handler.error", stats.Tags{"origin": reason}, int64(1))
	if addToDlq {
		h.AddToDeadLetterQueue(ctx, logger, rr.Payload, stats.Tags{"origin": reason})
	}
}
