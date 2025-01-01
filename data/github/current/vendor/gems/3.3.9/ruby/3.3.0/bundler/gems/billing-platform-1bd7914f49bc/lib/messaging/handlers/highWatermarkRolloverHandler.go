package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydroSchemaEntities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/messaging"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	schemas "github.com/github/hydro-client-go/v5/generated/hydro/schemas/hydro/v1"
	protobuf "github.com/golang/protobuf/proto" //nolint:staticcheck
	"github.com/pkg/errors"
	"go.uber.org/ratelimit"
	"golang.org/x/sync/errgroup"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type HighWatermarkRolloverHandler struct {
	*Handler
	usageEngine        *engines.UsageEngine
	subscriptionEngine *engines.SubscriptionsEngine
}

func NewHighWatermarkRolloverHandler(
	params *HandlerParams,
	usageEngine *engines.UsageEngine,
	subscriptionEngine *engines.SubscriptionsEngine,
) *HighWatermarkRolloverHandler {
	return &HighWatermarkRolloverHandler{
		Handler:            NewHandler(params, models.WorkerTypeHighWatermarkRolloverHandler),
		usageEngine:        usageEngine,
		subscriptionEngine: subscriptionEngine,
	}
}

func (h *HighWatermarkRolloverHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	h.statter.Counter("high_watermark_rollover_job.start", stats.Tags{}, 1)

	var job *models.HighWatermarkRolloverJob
	if err := json.Unmarshal(rr.Payload, &job); err != nil {
		h.TrackEmissionErrorAndAddToDLQ(ctx, logger, rr, "", "unmarshal_error", errors.Wrap(err, "failed to unmarshal high-watermark-rollover job"))
		return nil
	}
	logger = logger.WithFields(kvp.String("CustomerId", job.JobRun.CustomerId))
	jobTime := models.NewUsageTime().WithYear(job.JobRun.Year).WithMonthInt(job.JobRun.Month).WithDay(1).WithHour(0)

	logger.Info("performing rollover job for high watermark billing", kvp.String("jobTime", jobTime.String()))
	err := h.performRolloverChargeForCustomer(ctx, logger, job.JobRun.CustomerId, job.JobRun.Sku, jobTime, job.JobRun.DryRun)
	if err != nil {
		h.TrackEmissionErrorAndAddToDLQ(ctx, logger, rr, job.JobRun.Sku, "customer.highWatermarkRolloverJobFailed", err, kvp.String("sku", job.JobRun.Sku), kvp.String("customerId", job.JobRun.CustomerId))
		return nil
	}
	h.statter.Counter("high_watermark_rollover_job.end", stats.Tags{}, 1)
	return nil
}

func (h *HighWatermarkRolloverHandler) TrackEmissionErrorAndAddToDLQ(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult, sku string, reason string, err error, fields ...kvp.Field) {
	fields = append(fields, kvp.String("origin", reason))
	logger.WithError(err).Error("error processing high watermark rollover job", fields...)
	h.AddToDeadLetterQueue(ctx, logger, rr.Payload, stats.Tags{"origin": reason})
	h.statter.Counter("high_watermark_rollover_job.errors", stats.Tags{"origin": reason, "sku": sku}, int64(1))
}

func (h *HighWatermarkRolloverHandler) performRolloverChargeForCustomer(ctx context.Context, logger log.Logger, customerId string, sku string, jobTime *models.UsageTime, dryRun bool) error {
	subscribedItemsRequest := &proto.GetSubscribedItemsRequest{
		UsageEntityId: customerId,
		Sku:           sku,
	}
	subscriptionItems, err := h.subscriptionEngine.GetActiveSubscribedItems(ctx, logger, subscribedItemsRequest)
	h.statter.Counter("high_watermark_rollover_job.active_subscribed_items", stats.Tags{"sku": sku}, int64(len(subscriptionItems)))

	if err != nil {
		return errors.Wrap(err, fmt.Sprintf("error getting subscribed items for customer %s", customerId))
	}

	// Send events to the job on a timer
	h.throttleUsageEvents(ctx, logger, customerId, jobTime, subscriptionItems, dryRun)

	logger.Info("high-watermark-rollover-job-processed-for-customer", kvp.String("customerId", customerId), kvp.String("sku", sku))

	return nil
}

func (h *HighWatermarkRolloverHandler) throttleUsageEvents(ctx context.Context, logger log.Logger, customerId string, jobTime *models.UsageTime, subscriptionItems []*models.SubscribedItem, dryRun bool) {
	customerIdAsInt, _ := strconv.ParseInt(customerId, 10, 64)
	rateLimiter := ratelimit.New(10) // per second

	for _, subscribedItem := range subscriptionItems {
		// Wait for the rate limiter before sending the event
		_ = rateLimiter.Take()

		rolloverHwbHydroEvent := h.buildRolloverUsage(ctx, jobTime, subscribedItem, customerIdAsInt)

		if dryRun {
			logger.Info("Dry run", kvp.Any("event", rolloverHwbHydroEvent), kvp.Bool("dryRun", dryRun))
		} else {
			logger.Info("sending high-watermark-rollover job to aqueduct", kvp.Any("event", rolloverHwbHydroEvent), kvp.Bool("dryRun", dryRun))

			err := h.sendEvent(ctx, logger, rolloverHwbHydroEvent)
			if err != nil {
				logger.WithError(err).Error(fmt.Sprintf("error sending high watermark rollover job to aqueduct. customerID:%s, sku:%s", customerId, subscribedItem.Sku))
			}

			h.statter.Counter("high-watermark-rollover-job-event-sent", stats.Tags{"customerId": customerId}, 1)
		}

		// Check if the context is done after sending the event
		select {
		case <-ctx.Done():
			return
		default:
			// Continue if the context is not done
		}
	}
}

func (h *HighWatermarkRolloverHandler) buildRolloverUsage(ctx context.Context, jobTime *models.UsageTime, subscribedItem *models.SubscribedItem, customerIdAsInt int64) *hydroSchema.Usage {
	usageAt := jobTime.Time
	todayTimeStamp := timestamppb.New(usageAt)
	usageUuid := fmt.Sprintf(
		"%d:%s:%d:%s:%d:%d",
		customerIdAsInt,
		"high_watermark_rollover",
		subscribedItem.EntityDetail.ActorId,
		subscribedItem.Sku,
		todayTimeStamp.AsTime().Year(), todayTimeStamp.AsTime().Month())

	usage := &hydroSchema.Usage{
		Sku:       subscribedItem.Sku,
		Quantity:  subscribedItem.SubscriptionStatus.ToQuantity(),
		SourceUri: models.RollOverFromPreviousMonth,
		UsageAt:   todayTimeStamp,
		Entity: &hydroSchemaEntities.EntityDetail{
			CustomerId: customerIdAsInt,
			ActorId:    subscribedItem.EntityDetail.ActorId,
		},
		UsageUuid: usageUuid,
	}
	return usage
}

func (h *HighWatermarkRolloverHandler) sendEvent(ctx context.Context, logger log.Logger, hydroEvent *hydroSchema.Usage) error {
	usageAsBytes, err := protobuf.Marshal(hydroEvent)
	if err != nil {
		return errors.Wrap(err, "error marshalling usage event")
	}

	envelope := schemas.Envelope{
		Message: usageAsBytes,
	}
	envelopeBytes, err := protobuf.Marshal(&envelope)
	if err != nil {
		return errors.Wrap(err, "error marshalling envelope")
	}

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
		l.WithError(err).Error("error submitting high-watermark-rollover job to aqueduct")
	}
	return nil
}

type ScheduleHighWatermarkJobHandler struct {
	usageEngine *engines.UsageEngine
}

func (h *ScheduleHighWatermarkJobHandler) Handle(ctx context.Context, logger log.Logger, data json.RawMessage) error {
	// Get the high watermark rollover job run from the message
	var jobRun *models.HighWatermarkRolloverJobRun
	if err := json.Unmarshal(data, &jobRun); err != nil {
		return errors.Wrap(err, "failed to unmarshal high-watermark-rollover job run")
	}

	var highWatermarkSkus []string
	if len(jobRun.Sku) == 0 {
		now := time.Now().UTC()
		for _, pricing := range engines.AllProductSkuV2() {
			if (pricing.IsEnabled(now)) && (pricing.MeterType == models.PricingMeterDailyUnitCharge) {
				highWatermarkSkus = append(highWatermarkSkus, pricing.Sku)
			}
		}
	} else {
		highWatermarkSkus = append(highWatermarkSkus, jobRun.Sku)
	}

	g, gctx := errgroup.WithContext(ctx)

	// Schedule jobs
	for _, sku := range []string(highWatermarkSkus) {
		skuToRunWith := sku
		g.Go(func() error {
			// Schedule high watermark rollover job
			return h.usageEngine.ScheduleHighWatermarkRolloverJobs(gctx, logger, jobRun.WithSku(skuToRunWith))
		})
	}

	if err := g.Wait(); err != nil {
		return errors.Wrap(err, "failed to schedule high-watermark-rollover jobs")
	}
	return nil
}
