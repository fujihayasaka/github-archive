package transitions

import (
	"context"
	"fmt"

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

type DeletePartitionDataTransition struct {
	ctx         context.Context
	cfg         *config.Config
	logger      log.Logger
	db          interfaces.Database
	itemQuerier db.ModelQuerier[*models.Item]
}

func NewDeletePartitionDataTransitionWithQuerier(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	db interfaces.Database,
	querier db.ModelQuerier[*models.Item],
) *DeletePartitionDataTransition {
	return &DeletePartitionDataTransition{
		ctx:         ctx,
		cfg:         cfg,
		logger:      logger,
		db:          db,
		itemQuerier: querier,
	}
}

func NewDeletePartitionDataTransition(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	dbs interfaces.Database,
) *DeletePartitionDataTransition {
	return NewDeletePartitionDataTransitionWithQuerier(ctx, cfg, logger, dbs, db.NewQuerier[*models.Item](dbs))
}

func (t *DeletePartitionDataTransition) Run(dryRun bool, partitionKey string, limit int, rate int) error {
	if partitionKey == "" {
		return errors.New("partition key is required")
	}

	if limit <= 0 {
		return errors.New("limit greater than zero is required")
	}

	if rate <= 0 {
		return errors.New("rate greater than zero is required")
	}

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
			t.logger.Info("Starting deletion of batch", kvp.String("partitionKey", partitionKey), kvp.Int("batchNum", batchNum), kvp.Int("itemCount", len(batch)))
			if dryRun {
				t.logger.Info("Dry run mode enabled, no data will be deleted")
				return nil
			}

			t.logger.Info("Starting deletion of partition data", kvp.String("partitionKey", partitionKey), kvp.Int("itemCount", len(batch)))
			err := t.DeletePartitionData(gctx, batch)
			if err != nil {
				t.logger.WithError(err).Error("Batch deletion failed", kvp.String("partitionKey", partitionKey), kvp.Int("batchNum", batchNum))
			}

			return nil
		})
	}

	if err := <-errCh; err != nil {
		t.logger.WithError(err).Error("QueryItemsAsyncBatch failed", kvp.String("partitionKey", partitionKey))
		return errors.Wrap(err, "failed to query items")
	}

	// Wait for all processing goroutines to finish
	if err := g.Wait(); err != nil {
		t.logger.WithError(err).Error("one of the goroutines failed", kvp.String("partitionKey", partitionKey))
	}

	return nil
}

func (t DeletePartitionDataTransition) DeletePartitionData(ctx context.Context, data []*models.Item) error {
	options := &interfaces.QueryOptions{
		RetryCount: 10,
	}

	for _, item := range data {
		t.logger.Info("DeleteWithOptions", kvp.String("Key", item.Key.Id))
		err := t.db.DeleteWithOptions(ctx, t.logger, &item.Key, options)
		if err != nil {
			return errors.Wrap(err, "failed to delete item")
		}
	}

	return nil
}
