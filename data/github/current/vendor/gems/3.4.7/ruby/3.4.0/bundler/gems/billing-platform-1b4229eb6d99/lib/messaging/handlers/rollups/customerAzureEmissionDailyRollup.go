package rollups

import (
	"context"

	stats "github.com/github/go-stats"

	"github.com/github/billing-platform/lib/messaging/handlers"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/log"
	"golang.org/x/sync/errgroup"
)

func NewCustomerAzureEmissionDailyRollupHandler(
	params *handlers.HandlerParams,
) *handlers.RollupHandler {

	return handlers.NewRollupHandler(
		params,
		doCustomerAzureEmissionDailyRollup,
		models.WorkerTypeCustomerAzureEmissionDailyRollup,
		"CustomerAzureEmissionDailyRollup",
		handlers.WithRateLimit(1000),
	)
}

func doCustomerAzureEmissionDailyRollup(ctx context.Context, logger log.Logger, item models.Item, eg *errgroup.Group, handler *handlers.RollupHandler) error {
	item.Id = item.PartitionKey

	eg.Go(func() error {
		err := handler.PatchOrCreate(ctx, logger, item.AsMonthlyItemWithMonthlyPartitionKeyofType(models.ByCustomerSku, models.BySkuAzureEmission))
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Daily, item, models.NormalUsageAggregation, models.ByCustomerSku, models.BySkuAzureEmission, nil)
			handler.AddToFailedRollupQueue(ctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerSku"})
		}
		return nil
	})

	return nil
}
