package rollups

import (
	"context"

	"github.com/github/billing-platform/lib/messaging/handlers"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"golang.org/x/sync/errgroup"
)

func NewCustomerMonthlyRollupHandler(
	params *handlers.HandlerParams,
) *handlers.RollupHandler {
	return handlers.NewRollupHandler(
		params,
		doCustomerMonthlyRollup,
		models.WorkerTypeCustomerMonthlyRollup,
		"CustomerMonthlyRollup",
		handlers.WithRateLimit(100),
	)
}

func doCustomerMonthlyRollup(gctx context.Context, logger log.Logger, item models.Item, errgroup *errgroup.Group, handler *handlers.RollupHandler) error {
	discountItem, err := handler.GetHourlyDiscountItem(gctx, logger, item)
	if err != nil {
		return err
	}

	originalId := item.Id

	errgroup.Go(func() error {
		item.Id = originalId
		discountCopy, err := discountItem.DeepCopy()
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Monthly, item, models.DiscountUsageAggregation, models.ByCustomer, models.ByCustomer, nil)
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomer"})
			return nil
		}

		err = handler.PatchDiscount(gctx, logger, item, discountCopy, models.Daily, models.Monthly, models.ByCustomer)
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Monthly, item, models.DiscountUsageAggregation, models.ByCustomer, models.ByCustomer, nil)
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomer"})
			return nil
		}
		return nil
	})
	errgroup.Go(func() error {
		item.Id = originalId
		discountCopy, err := discountItem.DeepCopy()
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Monthly, item, models.DiscountUsageAggregation, models.ByCustomerSku, models.ByCustomerSku, nil)
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerSku"})
			return nil
		}

		err = handler.PatchDiscount(gctx, logger, item, discountCopy, models.Daily, models.Monthly, models.ByCustomerSku)
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Monthly, item, models.DiscountUsageAggregation, models.ByCustomerSku, models.ByCustomerSku, nil)
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerSku"})
			return nil
		}
		return nil
	})

	item.Id = item.PartitionKey
	errgroup.Go(func() error {
		dailyItemByCustomerOrgRepoProductSku := item.AsMonthlyItemWithPartitionKeyofType(models.ByOrgRepoProductSku, models.ByCustomerOrgRepoProductSku, []string{"ActorId", "SourceUri"})
		err := handler.PatchOrCreate(gctx, logger, dailyItemByCustomerOrgRepoProductSku)
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Monthly, item, models.NormalUsageAggregation, models.ByOrgRepoProductSku, models.ByCustomerOrgRepoProductSku, []string{"ActorId", "SourceUri"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByOrgRepoProductSku"})
		}

		item.Id = originalId
		discountCopy, err := discountItem.DeepCopy()
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Monthly, item, models.DiscountUsageAggregation, models.ByCustomerOrgRepoProductSku, models.ByCustomerOrgRepoProductSku, []string{"ActorId", "SourceUri"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerOrgRepoProductSku"})
			return nil
		}

		err = handler.PatchDiscount(gctx, logger, item, discountCopy, models.Daily, models.Monthly, models.ByCustomerOrgRepoProductSku)
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Monthly, item, models.DiscountUsageAggregation, models.ByCustomerOrgRepoProductSku, models.ByCustomerOrgRepoProductSku, []string{"ActorId", "SourceUri"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerOrgRepoProductSku"})
		}
		return nil
	})
	errgroup.Go(func() error {
		err := handler.PatchOrCreate(gctx, logger, item.AsMonthlyItemWithPartitionKeyofType(models.ByCustomerSku, models.ByCustomer, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"}))
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Monthly, item, models.NormalUsageAggregation, models.ByCustomerSku, models.ByCustomer, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, nil)
		}
		return nil
	})
	errgroup.Go(func() error {
		err := handler.PatchOrCreate(gctx, logger, item.AsMonthlyItemWithPartitionKeyofType(models.ByCustomerSku, models.ByCustomerSku, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"}))
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Monthly, item, models.NormalUsageAggregation, models.ByCustomerSku, models.ByCustomerSku, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerSku"})
		}
		return nil
	})
	errgroup.Go(func() error {
		err := handler.PatchOrCreate(gctx, logger, item.AsMonthlyItemWithPartitionKeyofType(models.ByCustomerSku, models.ByCustomerProduct, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"}))
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Monthly, item, models.NormalUsageAggregation, models.ByCustomerSku, models.ByCustomerProduct, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerSku"})
		}
		return nil
	})

	errgroup.Go(func() error {
		err := handler.PatchOrCreate(gctx, logger, item.AsMonthlyItemWithPartitionKeyofType(models.ByCustomerRepo, models.ByCustomerOrgRepo, []string{"Pricing", "SourceUri", "ActorId"}))
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Monthly, item, models.NormalUsageAggregation, models.ByCustomerRepo, models.ByCustomerOrgRepo, []string{"Pricing", "SourceUri", "ActorId"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerRepo"})
		}
		return nil
	})

	errgroup.Go(func() error {
		err := handler.PatchOrCreate(gctx, logger, item.AsMonthlyItemWithPartitionKeyofType(models.ByCustomerSku, models.ByCustomerRepoByProductSku, []string{"ActorId", "SourceUri"}))
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Monthly, item, models.NormalUsageAggregation, models.ByCustomerSku, models.ByCustomerRepoByProductSku, []string{"ActorId", "SourceUri"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerSku"})
		}

		item.Id = originalId
		discountCopy, err := discountItem.DeepCopy()
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Monthly, item, models.DiscountUsageAggregation, models.ByCustomerRepoByProductSku, models.ByCustomerRepoByProductSku, []string{"ActorId", "SourceUri"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerRepoByProductSku"})
			return nil
		}

		err = handler.PatchDiscount(gctx, logger, item, discountCopy, models.Daily, models.Monthly, models.ByCustomerRepoByProductSku)
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Monthly, item, models.DiscountUsageAggregation, models.ByCustomerRepoByProductSku, models.ByCustomerRepoByProductSku, []string{"ActorId", "SourceUri"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerRepoByProductSku"})
		}
		return nil
	})
	errgroup.Go(func() error {
		err := handler.PatchOrCreate(gctx, logger, item.AsMonthlyItemWithPartitionKeyofType(models.ByCustomerSku, models.ByCustomerOrgByProductSku, []string{"ActorId", "RepositoryId", "SourceUri"}))
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Monthly, item, models.NormalUsageAggregation, models.ByCustomerSku, models.ByCustomerOrgByProductSku, []string{"ActorId", "RepositoryId", "SourceUri"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerSku"})
		}

		item.Id = originalId
		discountCopy, err := discountItem.DeepCopy()
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Monthly, item, models.DiscountUsageAggregation, models.ByCustomerOrgByProductSku, models.ByCustomerOrgByProductSku, []string{"ActorId", "RepositoryId", "SourceUri"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerOrgByProductSku"})
			return nil
		}

		err = handler.PatchDiscount(gctx, logger, item, discountCopy, models.Daily, models.Monthly, models.ByCustomerOrgByProductSku)
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Monthly, item, models.DiscountUsageAggregation, models.ByCustomerOrgByProductSku, models.ByCustomerOrgByProductSku, []string{"ActorId", "RepositoryId", "SourceUri"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerOrgByProductSku"})
		}
		return nil
	})

	return nil
}
