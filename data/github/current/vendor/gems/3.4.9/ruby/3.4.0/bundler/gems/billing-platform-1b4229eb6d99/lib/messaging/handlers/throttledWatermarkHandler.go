package handlers

import (
	"context"
	"strconv"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	schemas "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/proto"

	"github.com/github/billing-platform/internal/logging"
	"github.com/github/billing-platform/lib/messaging"
	"github.com/github/billing-platform/lib/models"
)

type ThrottledWatermarkHandler struct {
	*Handler
}

func NewThrottledWatermarkHandler(params *HandlerParams) *ThrottledWatermarkHandler {
	return &ThrottledWatermarkHandler{
		Handler: NewHandler(params, models.WorkerTypeThrottledWatermark),
	}
}

func (h *ThrottledWatermarkHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	_, sp := h.tracer.Start(ctx, "ThrottledWatermarkHandler.ProcessMessage")
	defer sp.End()

	start := time.Now()
	logger.Info("received usage message")

	message, retErr := h.loadItem(rr.Payload)
	if retErr != nil {
		logger.WithError(retErr).Error("failed to load item")
		return retErr
	}

	logger.Info("message parsed successfully", kvp.String("sku", message.Sku), kvp.Int64("customer_id", message.Entity.CustomerId))

	// Send line items further to the usage ingestion handler
	job := aqueduct.Job{
		App:     h.cfg.AqueductApplication(),
		Queue:   messaging.GetQueueName(models.WorkerTypeUsageIngestion, h.cfg.OverrideQueuePrefix),
		Payload: rr.Payload,
	}

	retryCount := 10
	var err error
	for i := 0; i <= retryCount; i++ {
		_, err = h.aqueductClient.Send(ctx, job, []aqueduct.SendOption{aqueduct.WithJobMaxRedeliveryAttempts(10)}...)
		if err != nil {
			l := logger.WithFields(
				kvp.String("aqueduct.job.app", job.App),
				kvp.String("aqueduct.job.queue", job.Queue),
				kvp.Int64(logging.BillingCustomerId, message.Entity.CustomerId),
				kvp.String(logging.BillingPlatformSku, message.Sku),
				kvp.String(logging.BillingPlatformUsageItemUUID, message.UsageUuid),
			)
			l.WithError(err).Error("error submitting watermark for usage ingestion")
			time.Sleep(time.Duration(500) * time.Millisecond)
		} else {
			break
		}
	}

	h.statter.Counter(
		"throttled-watermark-handler-processed",
		stats.Tags{
			"product-sku": message.Sku,
			"success:":    strconv.FormatBool(retErr == nil),
		},
		int64(1))
	h.statter.Timing("throttled-watermark-handler-processed", nil, time.Since(start))

	return nil
}

func (h *ThrottledWatermarkHandler) loadItem(payload []byte) (*hydroSchema.Usage, error) {
	var envelope schemas.Envelope
	err := proto.Unmarshal(payload, &envelope)
	if err != nil {
		return nil, errors.Wrap(err, "failed to unmarshal payload")
	}

	var message hydroSchema.Usage
	err = proto.Unmarshal(envelope.Message, &message)
	if err != nil {
		return nil, errors.Wrap(err, "failed to unmarshal envelope")
	}

	return &message, nil
}
