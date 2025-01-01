package handlers

import (
	"context"
	"encoding/json"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"
	"golang.org/x/sync/errgroup"

	"go.uber.org/ratelimit"
)

type RollupFunc func(context.Context, log.Logger, models.Item, *errgroup.Group, *RollupHandler) error

type RollupHandlerOptions func(*RollupHandler)

const DefaultRateLimit = 1000

type RollupHandler struct {
	*Handler
	rollupName string
	doRollup   RollupFunc

	rateLimiter ratelimit.Limiter
}

func NewRollupHandler(
	params *HandlerParams,
	doRollup RollupFunc,
	workerType models.WorkerType,
	rollupName string,
	opts ...RollupHandlerOptions,
) *RollupHandler {
	rh := &RollupHandler{
		Handler:    NewHandler(params, workerType),
		rollupName: rollupName,
		doRollup:   doRollup,
	}

	for _, opt := range opts {
		opt(rh)
	}

	return rh
}

// WithRateLimit sets the rate limit for the rollup handler default is 1000 per second
func WithRateLimit(l int) func(*RollupHandler) {
	return func(h *RollupHandler) {
		if l == 0 {
			l = DefaultRateLimit
		}
		h.rateLimiter = ratelimit.New(l)
	}
}

// ProcessMessage processes the message and calls the doRollup function
func (h *RollupHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	logger.Info("Processing message in", kvp.String("queue", h.queueName), kvp.String("rollup", h.rollupName), kvp.Int("rollup_handler.job_delivery_attempt", rr.DeliveryAttempt))

	logger.Debug("unmarshalling enveloped message", kvp.String("queue", string(rr.Payload)))

	var item *models.Item
	if err := json.Unmarshal(rr.Payload, &item); err != nil {
		return errors.Wrap(err, "rollupHandler failed to unmarshal enveloped message")
	}

	start := time.Now()
	egrp, gctx := errgroup.WithContext(ctx)

	if h.rateLimiter != nil {
		h.rateLimiter.Take()
	}

	if err := h.doRollup(gctx, logger, *item, egrp, h); err != nil {
		logger.Error("rollupHandler ProcessMessage failed in doRollup", kvp.Any("customer", item.GetCustomerId()), kvp.Any("key", item.Key), kvp.Any("partitionKey", item.PartitionKey))
		h.statter.Counter("rollup_handler.do_rollup_failed", stats.Tags{"queue": h.queueName}, 1)

		// Returning nil instead of error here to avoid rollup job being retried from aqueduct. We retry using the failed rollup queue instead.
		return nil
	}

	if err := egrp.Wait(); err != nil {
		logger.Error("rollupHandler one or more errgroup go routines failed, showing first error only.", kvp.Any("customer", item.GetCustomerId()), kvp.Any("key", item.Key), kvp.Any("partitionKey", item.PartitionKey))
		h.statter.Counter("rollup_handler.egrp_rollup_failed", stats.Tags{"queue": h.queueName}, 1)

		// Returning nil instead of error here to avoid rollup job being retried from aqueduct. We retry using the failed rollup queue instead.
		return nil
	}

	h.statter.Timing("rollup-processed", stats.Tags{"queue": h.queueName}, time.Since(start))
	logger.Debug("processed usage message", kvp.Any("key", item.Key), kvp.Duration("duration", time.Since(start)))

	return nil
}
