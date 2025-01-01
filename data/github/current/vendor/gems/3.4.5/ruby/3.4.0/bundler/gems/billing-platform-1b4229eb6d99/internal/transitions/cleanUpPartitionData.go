package transitions

import (
	"context"
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/pkg/errors"
	"go.uber.org/ratelimit"
	"golang.org/x/sync/errgroup"

	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

// Transition to clean up partition data, maily to reduce the size of partitions close to reach 20 GB.

type CleanUpPartitionDataTransition struct {
	ctx         context.Context
	cfg         *config.Config
	logger      log.Logger
	db          interfaces.Database
	itemQuerier db.ModelQuerier[*models.Item]
}

func NewCleanUpPartitionDataTransitionWithQuerier(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	db interfaces.Database,
	querier db.ModelQuerier[*models.Item],
) *CleanUpPartitionDataTransition {
	return &CleanUpPartitionDataTransition{
		ctx:         ctx,
		cfg:         cfg,
		logger:      logger,
		db:          db,
		itemQuerier: querier,
	}
}

func NewCleanUpPartitionDataTransition(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	dbs interfaces.Database,
) *CleanUpPartitionDataTransition {
	return NewCleanUpPartitionDataTransitionWithQuerier(ctx, cfg, logger, dbs, db.NewQuerier[*models.Item](dbs))
}

func (t *CleanUpPartitionDataTransition) Run(dryRun bool, partitionKey string, limit int, rate int) error {
	if partitionKey == "" {
		return errors.New("partition key is required")
	}

	if limit <= 0 {
		return errors.New("limit greater than zero is required")
	}

	if rate <= 0 {
		return errors.New("rate greater than zero is required")
	}

	logger := t.logger.WithFields(kvp.String("gh.billing_platform.transition.partitionKey", partitionKey))

	queryWithLimit := fmt.Sprintf("SELECT * FROM c OFFSET 0 LIMIT %d", limit)
	keysCh, errCh := t.itemQuerier.QueryItemsAsyncBatch(t.ctx, t.logger, queryWithLimit, partitionKey)
	g, gctx := errgroup.WithContext(t.ctx)

	batchNum := 0
	rateLimiter := ratelimit.New(rate)
	for keys := range keysCh {
		_ = rateLimiter.Take()

		batch := keys
		g.Go(func() error {
			batchNum++
			logger.Info("Starting update of batch", kvp.Int("gh.billing_platform.transition.batchNum", batchNum), kvp.Int("gh.billing_platform.transition.itemCount", len(batch)))
			if dryRun {
				logger.Info("Dry run mode enabled, no data will be patched")
				return nil
			}

			logger.Info("Starting update of partition data", kvp.Int("gh.billing_platform.transition.itemCount", len(batch)))
			err := t.CleanUpPartitionData(gctx, batch)
			if err != nil {
				logger.WithError(err).Error("Batch update failed", kvp.Int("gh.billing_platform.transition.batchNum", batchNum))
			}

			return nil
		})
	}

	if err := <-errCh; err != nil {
		logger.WithError(err).Error("QueryItemsAsyncBatch failed")
		return errors.Wrap(err, "failed to query items")
	}

	// Wait for all processing goroutines to finish
	if err := g.Wait(); err != nil {
		logger.WithError(err).Error("one of the goroutines failed")
	}

	return nil
}

func (t CleanUpPartitionDataTransition) CleanUpPartitionData(ctx context.Context, data []*models.Item) error {
	// Expecting to target partition [customerId]:actions_storage:events:[year]:[month].
	// The only required fields are the partition key and id, used for idempotency checks.
	po := azcosmos.PatchOperations{}
	po.AppendRemove("/BilledAmount")
	po.AppendRemove("/FullQuantity")
	po.AppendRemove("/Quantity")
	po.AppendRemove("/AppliedCostPerQuantity")
	po.AppendRemove("/FractionalQuantity")
	po.AppendRemove("/Pricing")
	po.AppendRemove("/EntityDetail")

	options := &interfaces.QueryOptions{
		RetryCount: 10,
	}

	for _, item := range data {
		t.logger.WithFields(
			kvp.String("gh.billing_platform.transition.partitionKey", item.Key.PartitionKey),
			kvp.String("gh.billing_platform.transition.documentId", item.Key.Id),
		).Info("PatchWithOptions")
		err := t.db.PatchWithOptions(ctx, t.logger, item, po, options)
		if err != nil {
			return errors.Wrap(err, "failed to patch item")
		}
	}

	return nil
}
