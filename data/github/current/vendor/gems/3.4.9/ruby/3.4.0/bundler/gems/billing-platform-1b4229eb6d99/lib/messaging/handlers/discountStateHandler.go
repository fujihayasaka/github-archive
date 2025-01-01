package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	stats "github.com/github/go-stats"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

type DiscountStateHandler struct {
	*Handler
	discountEngine engines.DiscountEngineInterface
}

func NewDiscountStateHandler(
	params *HandlerParams,
	discountEngine engines.DiscountEngineInterface,
) *DiscountStateHandler {
	return &DiscountStateHandler{
		Handler:        NewHandler(params, models.WorkerTypeDiscountStateUpdate),
		discountEngine: discountEngine,
	}
}

func (h *DiscountStateHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	logger.Info("Processing message in", kvp.String("queue", h.queueName), kvp.Int("aqueduct.job_delivery_attempt", rr.DeliveryAttempt))

	start := time.Now()
	defer func() {
		h.statter.Timing("discount.state.update_duration", stats.Tags{}, time.Since(start))
	}()

	var discountStateUpdatePayload models.UpdateDiscountStatePayload
	if err := json.Unmarshal(rr.Payload, &discountStateUpdatePayload); err != nil {
		h.TrackEmissionError(logger, err, "unmarshal_payload")
		return nil
	}

	err := h.discountEngine.UpdateDiscountState(ctx, logger, discountStateUpdatePayload)
	if err != nil {
		h.TrackEmissionError(logger, err, "update_discount_state")
		return err
	}

	h.statter.Counter("discount.state.update", stats.Tags{"delivery_attempt": fmt.Sprintf("%d", rr.DeliveryAttempt)}, 1)

	h.statter.Timing("discount.state.apply_update_duration", stats.Tags{}, time.Since(discountStateUpdatePayload.CreatedAt))

	return nil
}

func (h *DiscountStateHandler) TrackEmissionError(logger log.Logger, err error, reason string) {
	logger.WithError(err).Error(reason)
	h.statter.Counter("discount.state.error", stats.Tags{"reason": reason}, int64(1))
}
