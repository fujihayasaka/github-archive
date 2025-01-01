package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/messaging"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/feature-management-client-go/vexi"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
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
	flagger        *vexi.Client
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
	flagger *vexi.Client,
	totalsPatching *engines.TotalPatchingEngine,
) *HandlerParams {
	return &HandlerParams{
		cfg:                 cfg,
		aqueductClient:      aqueductClient,
		DB:                  db,
		statter:             statter,
		tracer:              tracer,
		flagger:             flagger,
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

func (h *Handler) AddToDeadLetterQueue(ctx context.Context, logger log.Logger, payload []byte, tags stats.Tags) error {
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

	return errors.Wrap(err, "failed to add message to dead letter queue")
}

func (h *Handler) PatchOrCreate(ctx context.Context, logger log.Logger, item interfaces.Patchable) error {
	return h.TotalsPatching.PatchOrCreate(ctx, logger, item)
}

func (h *Handler) GetHourlyDiscountItem(ctx context.Context, logger log.Logger, item models.Item) (*models.DiscountItem, error) {
	// we should always read from models.ByCustomerOrgRepoProductSku since this is the only item we write hourly discount items for
	key := &models.Key{
		Id:           item.Id,
		PartitionKey: models.GetDiscountPartitionKey((item.GetPartitionKey(models.Hourly, models.ByCustomerOrgRepoProductSku))),
	}
	discountItem, err := db.NewQuerier[*models.DiscountItem](h.DB).ReadItem(ctx, logger, key, nil)
	if err != nil {
		return nil, err
	}

	return discountItem, nil
}

func (h *Handler) GetAndPatchDiscount(ctx context.Context, logger log.Logger, item models.Item, from models.ActiveType, to models.ActiveType, upt models.UsagePartitionType) error {
	discountItem, err := h.GetHourlyDiscountItem(ctx, logger, item)
	if err != nil {
		return err
	}

	return h.PatchDiscount(ctx, logger, item, discountItem, from, to, upt)
}

func (h *Handler) PatchDiscount(ctx context.Context, logger log.Logger, item models.Item, discountItem *models.DiscountItem, from models.ActiveType, to models.ActiveType, upt models.UsagePartitionType) error {
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

		retryCount := 10
		var err error
		for i := 0; i < retryCount; i++ {
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

func (h *Handler) AddToBudgetStateQueue(ctx context.Context, logger log.Logger, payload models.BudgetStateUpdateJob, tags stats.Tags) {
	logger.Info("adding budget state update to budget state queue")

	payloadBytes, err := json.Marshal(&payload)
	if err != nil {
		h.statter.Counter("budget_state_handler.marshaling_error", stats.Tags{}, int64(1))
		logger.WithError(err).Error("failed to marshal payload for retry job")
	} else {
		job := aqueduct.Job{
			App:     h.appName,
			Queue:   h.GetQueueName(models.WorkerTypeBudgetState),
			Payload: payloadBytes,
		}

		retryCount := 10
		var err error
		for i := 0; i < retryCount; i++ {
			_, err = h.aqueductClient.Send(ctx, job, []aqueduct.SendOption{aqueduct.WithJobMaxRedeliveryAttempts(1000)}...)
			if err != nil {
				logger.WithError(err).Error(fmt.Sprintf("failed to add message to %s queue", job.Queue),
					kvp.String("queue_name", job.Queue),
					kvp.Int("retry_count", i+1))

				t := stats.Tags{"retry_count": strconv.Itoa(i + 1), "queue_name": job.Queue}
				h.statter.Counter("failure_to_aqueduct_send", t.Merge(tags), int64(1))

				time.Sleep(time.Duration(500) * time.Millisecond)
			} else {
				return
			}
		}
	}
}

func (h *Handler) PatchOrCreateLateDiscount(ctx context.Context, logger log.Logger, lateDiscountItem *models.LateDiscountItem) error {
	if h.patchLateDiscount(ctx, logger, lateDiscountItem) == nil {
		return nil
	}

	if h.DB.CreateWithOptions(ctx, logger, lateDiscountItem, nil) == nil {
		return nil
	}
	return h.patchLateDiscount(ctx, logger, lateDiscountItem)
}

func (h *Handler) patchLateDiscount(ctx context.Context, logger log.Logger, lateDiscountItem *models.LateDiscountItem) error {
	po := azcosmos.PatchOperations{}
	po.AppendIncrement("/DiscountAmount", lateDiscountItem.DiscountAmount)
	po.AppendIncrement("/Quantity", lateDiscountItem.Quantity)
	err := h.DB.PatchWithOptions(ctx, logger, lateDiscountItem, po, nil)
	if err != nil {
		return err
	}
	return nil
}

func (h *Handler) AddToDiscountStateUpdateQueue(ctx context.Context, logger log.Logger, payloads []models.UpdateDiscountStatePayload, sku string) {
	ctx, sp := h.tracer.Start(ctx, "Handler.AddToDiscountStateUpdateQueue")
	defer sp.End()

	logger.Info("adding discount state updates to discount state update queue")

	for _, payload := range payloads {
		payloadBytes, err := json.Marshal(&payload)
		if err != nil {
			h.statter.Counter("discount_state_update.marshaling_error", stats.Tags{}, int64(1))
			logger.WithError(err).Error("failed to marshal payload for discount state update")
			continue
		} else {
			job := aqueduct.Job{
				App:     h.appName,
				Queue:   h.GetQueueName(models.WorkerTypeDiscountStateUpdate),
				Payload: payloadBytes,
			}

			retryCount := 5
			var err error
			for i := 0; i <= retryCount; i++ {
				_, err = h.aqueductClient.Send(ctx, job, []aqueduct.SendOption{aqueduct.WithJobMaxRedeliveryAttempts(1000)}...)
				if err != nil {
					logger.WithError(err).Error("failed to add message to discount state update queue",
						kvp.String("queue_name", job.Queue),
						kvp.Int("retry_count", i+1),
					)
					h.statter.Counter("failure_to_aqueduct_send", stats.Tags{"sku": sku, "queue_name": job.Queue}, int64(1))
				} else {
					break
				}
			}

			if err != nil {
				h.statter.Counter("failure_to_aqueduct_send.number_of_retries_exceeded", stats.Tags{"sku": sku, "queue_name": job.Queue}, int64(1))
			}
		}
	}
}
