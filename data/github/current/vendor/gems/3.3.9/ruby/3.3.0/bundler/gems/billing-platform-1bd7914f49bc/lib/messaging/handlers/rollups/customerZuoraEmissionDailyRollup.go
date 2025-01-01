package rollups

import (
	"context"
	"time"

	stats "github.com/github/go-stats"

	"github.com/github/billing-platform/lib/messaging/handlers"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"golang.org/x/sync/errgroup"
)

func NewCustomerZuoraEmissionDailyRollupHandler(
	params *handlers.HandlerParams,
) *handlers.RollupHandler {

	return handlers.NewRollupHandler(
		params,
		doCustomerZuoraEmissionDailyRollup,
		models.WorkerTypeCustomerZuoraEmissionDailyRollup,
		"CustomerZuoraEmissionDailyRollup",
		handlers.WithRateLimit(1000),
	)
}

func doCustomerZuoraEmissionDailyRollup(ctx context.Context, logger log.Logger, item models.Item, eg *errgroup.Group, handler *handlers.RollupHandler) error {
	item.Id = item.PartitionKey
	eg.Go(func() error {
		err := handler.PatchOrCreate(ctx, logger, item.AsMonthlyItemWithMonthlyPartitionKeyofType(models.ByCustomerSku, models.ByCustomerZuoraEmission))
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Daily, item, models.NormalUsageAggregation, models.ByCustomerSku, models.ByCustomerZuoraEmission, nil)
			handler.AddToFailedRollupQueue(ctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerSku"})
		}
		currentDate := models.UTCNow().Truncate(24 * time.Hour)
		if item.UsageAt.Before(currentDate) {
			logger.Info("Late usage item detected: UsageAt date is earlier than the date in the original PartitionKey.",
				kvp.String("UsageAt", item.UsageAt.Time.String()),
				kvp.String("Id", item.Id),
				kvp.String("PartitionKey", item.PartitionKey))

			handler.HandlerParams.DB.GetStatter().Timing("customer-zuora-emission-daily-rollup-late-item", stats.Tags{"product-sku": item.GetSku()}, time.Since(item.UsageAt.Time))
		}
		return nil
	})

	return nil
}
