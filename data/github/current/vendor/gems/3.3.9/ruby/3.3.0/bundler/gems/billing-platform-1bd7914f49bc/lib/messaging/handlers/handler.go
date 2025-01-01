package handlers

import (
	"context"
	"encoding/json"
	"strconv"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/messaging"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	stats "github.com/github/go-stats"
)

type Handler struct {
	*HandlerParams
	queueName string
}

type HandlerParams struct {
	ProcessJobError error

	aqueductClient aqueduct.Client
	cfg            *config.Config
	DB             interfaces.Database
	statter        stats.Client
	tracer         trace.Tracer
	TotalsPatching *engines.TotalPatchingEngine

	appName             string
	overrideQueuePrefix string
}

func NewHandlerParams(
	aqueductClient aqueduct.Client,
	cfg *config.Config,
	db interfaces.Database,
	statter stats.Client,
	tracer trace.Tracer,
	totalsPatching *engines.TotalPatchingEngine,
) *HandlerParams {
	return &HandlerParams{
		cfg:                 cfg,
		aqueductClient:      aqueductClient,
		DB:                  db,
		statter:             statter,
		tracer:              tracer,
		appName:             cfg.AqueductApplication(),
		overrideQueuePrefix: cfg.OverrideQueuePrefix,
		TotalsPatching:      totalsPatching,
	}
}

func NewHandler(
	params *HandlerParams,
	workerType models.WorkerType,
) *Handler {
	return &Handler{
		HandlerParams: params,
		queueName:     messaging.GetQueueName(workerType, params.overrideQueuePrefix),
	}
}

func (h *Handler) ReceiveQueueName() string {
	return h.queueName
}

func (h *Handler) GetProcessJobError() error {
	return h.ProcessJobError
}

func (h *Handler) GetQueueName(workerType models.WorkerType) string {
	return messaging.GetQueueName(workerType, h.overrideQueuePrefix)
}

func (h *Handler) AddToDeadLetterQueue(ctx context.Context, logger log.Logger, payload []byte, tags stats.Tags) {
	job := aqueduct.Job{
		App:     h.appName,
		Queue:   messaging.GetDeadLetterQueueName(h.ReceiveQueueName()),
		Payload: payload,
	}

	_, err := h.aqueductClient.Send(ctx, job, messaging.MessageSenderOptions()...)
	if err != nil {
		logger.WithError(err).Error("failed to add message to dead letter queue",
			kvp.String("queue_name", job.Queue),
			kvp.String("payload", string(payload)),
		)
	}

	t := stats.Tags{"queue_name": job.Queue, "success": strconv.FormatBool(err == nil)}
	h.statter.Counter("add_to_dead_letter_queue", t.Merge(tags), int64(1))
}

func (h *Handler) PatchOrCreate(ctx context.Context, logger log.Logger, item interfaces.Patchable) error {
	return h.TotalsPatching.PatchOrCreate(ctx, logger, item)
}

func (h *Handler) PatchDiscount(ctx context.Context, logger log.Logger, item models.Item, from models.ActiveType, to models.ActiveType, upt models.UsagePartitionType) error {
	key := &models.Key{
		Id:           item.Id,
		PartitionKey: models.GetDiscountPartitionKey((item.GetPartitionKey(models.Hourly, upt))),
	}
	discountItem, err := db.NewQuerier[*models.DiscountItem](h.DB).ReadItem(ctx, logger, key, nil)

	if err != nil {
		return err
	}

	if discountItem == nil {
		return nil
	}

	if upt == models.ByCustomerOrgRepoProductSku {
		return h.PatchOrCreateDiscount(ctx, logger, discountItem.AsDiscountItemWithIdAndPartitionKeyForByCustomerOrgRepoProductSku(&item, from, to))
	} else {
		return h.PatchOrCreateDiscount(ctx, logger, discountItem.AsDiscountItemWithIdAndPartitionKeyOfType(&item, from, to, upt))
	}
}

func (h *Handler) PatchOrCreateDiscount(ctx context.Context, logger log.Logger, discountItem *models.DiscountItem) error {
	if h.patchDiscount(ctx, logger, discountItem) == nil {
		return nil
	}

	if h.DB.CreateWithOptions(ctx, logger, discountItem, nil) == nil {
		return nil
	}
	return h.patchDiscount(ctx, logger, discountItem)
}

func (h *Handler) patchDiscount(ctx context.Context, logger log.Logger, discountItem *models.DiscountItem) error {

	po := azcosmos.PatchOperations{}
	po.AppendIncrement("/DiscountAmount", discountItem.DiscountAmount)
	po.AppendIncrement("/Quantity", discountItem.Quantity)
	err := h.DB.PatchWithOptions(ctx, logger, discountItem, po, nil)
	if err != nil {
		return err
	}

	return nil
}

func (h *Handler) AddToFailedRollupQueue(ctx context.Context, logger log.Logger, payload models.FailedRollupJob, rollupErr error, tags stats.Tags) {
	logger.WithError(rollupErr).Error("rollup failed, adding to failed rollup queue")

	payloadBytes, err := json.Marshal(&payload)
	if err != nil {
		h.statter.Counter("failed_rollups.marshaling_error", stats.Tags{}, int64(1))
		logger.WithError(err).Error("failed to marshal payload for failed rollups")
	} else {
		job := aqueduct.Job{
			App:     h.appName,
			Queue:   messaging.GetFailedRollupsQueueName(),
			Payload: payloadBytes,
		}

		retryCount := 5
		var err error
		for i := 0; i <= retryCount; i++ {
			_, err = h.aqueductClient.Send(ctx, job, []aqueduct.SendOption{aqueduct.WithJobMaxRedeliveryAttempts(1000)}...)
			if err != nil {
				logger.WithError(err).Error("failed to add message to failed rollups queue",
					kvp.String("queue_name", job.Queue),
					kvp.Int("retry_count", i+1),
					kvp.Int("rollup_job.processor_type", int(payload.ProcessorType)),
					kvp.Int("rollup_job.aggregation_type", int(payload.AggregationType)),
					kvp.String("rollup_job.item.id", payload.Item.Id),
					kvp.String("rollup_job.item.partition_key", payload.Item.PartitionKey),
				)

				t := stats.Tags{"period": payload.ProcessorType.String(), "retry_count": strconv.Itoa(i + 1), "queue_name": job.Queue}
				h.statter.Counter("failure_to_aqueduct_send", t.Merge(tags), int64(1))

				time.Sleep(time.Duration(500) * time.Millisecond)
			} else {
				return
			}
		}
		if err != nil {
			t := stats.Tags{"period": payload.ProcessorType.String(), "queue_name": job.Queue}
			h.statter.Counter("failure_to_aqueduct_send.number_of_retries_exceeded", t.Merge(tags), int64(1))
		}
	}
}
