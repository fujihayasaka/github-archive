package rollups

import (
	"context"

	stats "github.com/github/go-stats"

	"github.com/github/billing-platform/lib/messaging/handlers"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/log"
	"golang.org/x/sync/errgroup"
)

func NewCustomerDailyRollupHandler(
	params *handlers.HandlerParams,
) *handlers.RollupHandler {
	return handlers.NewRollupHandler(
		params,
		doCustomerDailyRollup,
		models.WorkerTypeCustomerDailyRollup,
		"CustomerDailyRollup",
		handlers.WithRateLimit(100),
	)
}

func doCustomerDailyRollup(gctx context.Context, logger log.Logger, item models.Item, errgroup *errgroup.Group, handler *handlers.RollupHandler) error {
	originalId := item.Id
	item.Id = item.PartitionKey

	errgroup.Go(func() error {
		dailyItemByCustomer := item.AsDailyItemWithPartitionKeyofType(models.ByCustomerSku, models.ByCustomer, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
		err := handler.PatchOrCreate(gctx, logger, dailyItemByCustomer)
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Daily, item, models.NormalUsageAggregation, models.ByCustomerSku, models.ByCustomer, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerSku"})
		}

		item.Id = originalId
		err = handler.PatchDiscount(gctx, logger, item, models.Hourly, models.Daily, models.ByCustomer)
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Daily, item, models.DiscountUsageAggregation, models.ByCustomer, models.ByCustomer, nil)
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomer"})
		}
		return nil
	})
	errgroup.Go(func() error {
		dailyItemByCustomerSku := item.AsDailyItemWithPartitionKeyofType(models.ByCustomerSku, models.ByCustomerSku, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
		err := handler.PatchOrCreate(gctx, logger, dailyItemByCustomerSku)
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Daily, item, models.NormalUsageAggregation, models.ByCustomerSku, models.ByCustomerSku, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerSku"})
		}
		item.Id = originalId
		err = handler.PatchDiscount(gctx, logger, item, models.Hourly, models.Daily, models.ByCustomerSku)
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Daily, item, models.DiscountUsageAggregation, models.ByCustomerSku, models.ByCustomerSku, nil)
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerSku"})
		}
		return nil
	})
	errgroup.Go(func() error {
		dailyItemByCustomerOrgRepoProductSku := item.AsDailyItemWithPartitionKeyofType(models.ByOrgRepoProductSku, models.ByCustomerOrgRepoProductSku, nil)
		err := handler.PatchOrCreate(gctx, logger, dailyItemByCustomerOrgRepoProductSku)
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Daily, item, models.NormalUsageAggregation, models.ByOrgRepoProductSku, models.ByCustomerOrgRepoProductSku, nil)
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByOrgRepoProductSku"})
		}
		item.Id = originalId
		err = handler.PatchDiscount(gctx, logger, item, models.Hourly, models.Daily, models.ByCustomerOrgRepoProductSku)
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Daily, item, models.DiscountUsageAggregation, models.ByCustomerOrgRepoProductSku, models.ByCustomerOrgRepoProductSku, nil)
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerOrgRepoProductSku"})
		}
		return nil
	})

	errgroup.Go(func() error {
		err := handler.PatchOrCreate(gctx, logger, item.AsDailyItemWithPartitionKeyofType(models.ByCustomerSku, models.ByCustomerProduct, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"}))
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Daily, item, models.NormalUsageAggregation, models.ByCustomerSku, models.ByCustomerProduct, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerSku"})
		}
		return nil
	})
	errgroup.Go(func() error {
		err := handler.PatchOrCreate(gctx, logger, item.AsDailyItemWithPartitionKeyofType(models.ByCustomerRepo, models.ByCustomerOrgRepo, []string{"Pricing", "SourceUri", "ActorId"}))
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Daily, item, models.NormalUsageAggregation, models.ByCustomerRepo, models.ByCustomerOrgRepo, []string{"Pricing", "SourceUri", "ActorId"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerRepo"})
		}
		return nil
	})
	errgroup.Go(func() error {
		err := handler.PatchOrCreate(gctx, logger, item.AsDailyItemWithPartitionKeyofType(models.ByCustomerSku, models.ByCustomerRepoByProductSku, nil))
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Daily, item, models.NormalUsageAggregation, models.ByCustomerSku, models.ByCustomerRepoByProductSku, nil)
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerSku"})
		}
		return nil
	})
	errgroup.Go(func() error {
		err := handler.PatchOrCreate(gctx, logger, item.AsDailyItemWithPartitionKeyofType(models.ByCustomerSku, models.ByCustomerOrgByProductSku, nil))
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Daily, item, models.NormalUsageAggregation, models.ByCustomerSku, models.ByCustomerOrgByProductSku, nil)
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerSku"})
		}
		return nil
	})

	return nil
}
