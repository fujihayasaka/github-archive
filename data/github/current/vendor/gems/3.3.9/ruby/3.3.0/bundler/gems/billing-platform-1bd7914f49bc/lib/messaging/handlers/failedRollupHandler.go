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
)

type FailedRollupHandler struct {
	*Handler
}

func NewFailedRollupHandler(params *HandlerParams) *FailedRollupHandler {
	return &FailedRollupHandler{
		Handler: NewHandler(params, models.WorkerTypeFailedRollups),
	}
}

func (h *FailedRollupHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	logger.Info("Processing message in", kvp.String("queue", h.queueName), kvp.Int("failed_rollup_handler.job_delivery_attempt", rr.DeliveryAttempt))

	logger.Debug("unmarshalling enveloped message", kvp.String("payload", string(rr.Payload)))

	var failedRollupJob *models.FailedRollupJob
	if err := json.Unmarshal(rr.Payload, &failedRollupJob); err != nil {
		return errors.Wrap(err, "failedRollupHandler failed to unmarshal enveloped message")
	}

	start := time.Now()

	var item *models.Item
	var err error
	if failedRollupJob.AggregationType == models.NormalUsageAggregation {
		if failedRollupJob.KeysToIgnore == nil {
			failedRollupJob.KeysToIgnore = []string{}
		}
		switch failedRollupJob.ProcessorType {
		case models.Daily:
			item = failedRollupJob.Item.AsDailyItemWithPartitionKeyofType(failedRollupJob.From, failedRollupJob.To, failedRollupJob.KeysToIgnore)
		case models.Monthly:
			item = failedRollupJob.Item.AsMonthlyItemWithPartitionKeyofType(failedRollupJob.From, failedRollupJob.To, failedRollupJob.KeysToIgnore)
		case models.Yearly:
			item = failedRollupJob.Item.AsYearlyItemWithPartitionKeyofType(failedRollupJob.From, failedRollupJob.To, failedRollupJob.KeysToIgnore)
		}

		err = h.PatchOrCreate(ctx, logger, item)
	} else {
		var timeframe models.ActiveType
		switch failedRollupJob.ProcessorType {
		case models.Daily:
			timeframe = models.Hourly
		case models.Monthly:
			timeframe = models.Daily
		case models.Yearly:
			timeframe = models.Monthly
		}
		err = h.PatchDiscount(ctx, logger, failedRollupJob.Item, timeframe, failedRollupJob.ProcessorType, failedRollupJob.From)
	}

	h.statter.Timing("failed-rollover-processed", stats.Tags{"queue": h.queueName}, time.Since(start))
	if err != nil {
		logger.WithError(err).Error("failedRollupHandler failed to process failed rollup message, will be retried")
	}
	return err
}
