package rollups

import (
	"context"

	"github.com/github/billing-platform/lib/messaging/handlers"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"golang.org/x/sync/errgroup"
)

func NewCustomerYearlyRollupHandler(
	params *handlers.HandlerParams,
) *handlers.RollupHandler {
	return handlers.NewRollupHandler(
		params,
		doCustomerYearlyRollup,
		models.WorkerTypeCustomerYearlyRollup,
		"CustomerYearlyRollup",
		handlers.WithRateLimit(100),
	)
}

func doCustomerYearlyRollup(gctx context.Context, logger log.Logger, item models.Item, errgroup *errgroup.Group, handler *handlers.RollupHandler) error {
	originalId := item.Id

	errgroup.Go(func() error {
		item.Id = originalId
		err := handler.PatchDiscount(gctx, logger, item, models.Monthly, models.Yearly, models.ByCustomer)
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Yearly, item, models.DiscountUsageAggregation, models.ByCustomer, models.ByCustomer, nil)
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomer"})
		}
		return nil
	})
	errgroup.Go(func() error {
		item.Id = originalId
		err := handler.PatchDiscount(gctx, logger, item, models.Monthly, models.Yearly, models.ByCustomerSku)
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Yearly, item, models.DiscountUsageAggregation, models.ByCustomerSku, models.ByCustomerSku, nil)
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerSku"})
		}
		return nil
	})

	item.Id = item.PartitionKey
	errgroup.Go(func() error {
		err := handler.PatchOrCreate(gctx, logger, item.AsYearlyItemWithPartitionKeyofType(models.ByCustomerSku, models.ByCustomer, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"}))
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Yearly, item, models.NormalUsageAggregation, models.ByCustomerSku, models.ByCustomer, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerSku"})
		}
		return nil
	})
	errgroup.Go(func() error {
		err := handler.PatchOrCreate(gctx, logger, item.AsYearlyItemWithPartitionKeyofType(models.ByCustomerSku, models.ByCustomerSku, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"}))
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Yearly, item, models.NormalUsageAggregation, models.ByCustomerSku, models.ByCustomerSku, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerSku"})
		}
		return nil
	})
	errgroup.Go(func() error {
		yearlyItemByCustomerOrgRepoProductSku := item.AsYearlyItemWithPartitionKeyofType(models.ByOrgRepoProductSku, models.ByCustomerOrgRepoProductSku, nil)
		err := handler.PatchOrCreate(gctx, logger, yearlyItemByCustomerOrgRepoProductSku)
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Yearly, item, models.NormalUsageAggregation, models.ByOrgRepoProductSku, models.ByCustomerOrgRepoProductSku, nil)
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, nil)
		}

		item.Id = originalId
		err = handler.PatchDiscount(gctx, logger, item, models.Monthly, models.Yearly, models.ByCustomerOrgRepoProductSku)
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Yearly, item, models.DiscountUsageAggregation, models.ByCustomerOrgRepoProductSku, models.ByCustomerOrgRepoProductSku, nil)
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerOrgRepoProductSku"})
		}
		return nil
	})
	errgroup.Go(func() error {
		err := handler.PatchOrCreate(gctx, logger, item.AsYearlyItemWithPartitionKeyofType(models.ByCustomerSku, models.ByCustomerProduct, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"}))
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Yearly, item, models.NormalUsageAggregation, models.ByCustomerSku, models.ByCustomerProduct, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, nil)
		}
		return nil
	})

	errgroup.Go(func() error {
		err := handler.PatchOrCreate(gctx, logger, item.AsYearlyItemWithPartitionKeyofType(models.ByCustomerRepo, models.ByCustomerOrgRepo, []string{"Pricing", "SourceUri", "ActorId"}))
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Yearly, item, models.NormalUsageAggregation, models.ByCustomerRepo, models.ByCustomerOrgRepo, []string{"Pricing", "SourceUri", "ActorId"})
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerRepo"})
		}
		return nil
	})

	errgroup.Go(func() error {
		err := handler.PatchOrCreate(gctx, logger, item.AsYearlyItemWithPartitionKeyofType(models.ByCustomerSku, models.ByCustomerRepoByProductSku, nil))
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Yearly, item, models.NormalUsageAggregation, models.ByCustomerSku, models.ByCustomerRepoByProductSku, nil)
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerSku"})
		}
		return nil
	})
	errgroup.Go(func() error {
		err := handler.PatchOrCreate(gctx, logger, item.AsYearlyItemWithPartitionKeyofType(models.ByCustomerSku, models.ByCustomerOrgByProductSku, nil))
		if err != nil {
			rollupJobData := models.NewFailedRollupJob(models.Yearly, item, models.NormalUsageAggregation, models.ByCustomerSku, models.ByCustomerOrgByProductSku, nil)
			handler.AddToFailedRollupQueue(gctx, logger, *rollupJobData, err, stats.Tags{"rollup_type": "ByCustomerSku"})
		}
		return nil
	})

	return nil
}
