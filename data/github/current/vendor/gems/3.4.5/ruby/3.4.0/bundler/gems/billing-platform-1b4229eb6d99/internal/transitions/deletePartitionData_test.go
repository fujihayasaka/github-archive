package transitions

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/petergtz/pegomock/v4"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"golang.org/x/sync/errgroup"
)

func TestDeletePartitionDataTransition_Run(t *testing.T) {
	cfg := &config.Config{
		Environment: "test",
	}

	ctx := context.Background()
	telem, _ := telemetry.NewFromEnv()

	mocker := pegomock.WithT(t)
	mockDb := fakes.NewMockDatabase(mocker)
	mockItemQuerier := fakes.NewMockModelQuerier[*models.Item](mocker)

	key1 := models.Key{Id: "test1", PartitionKey: "partitionKey"}
	item1 := &models.Item{Key: key1}

	key2 := models.Key{Id: "test2", PartitionKey: "partitionKey"}
	item2 := &models.Item{Key: key2}

	itemsCh := make(chan []*models.Item)
	errCh := make(chan error)

	queryWithLimit := fmt.Sprintf("SELECT * FROM c OFFSET 0 LIMIT %d", 10)
	transition := NewDeletePartitionDataTransitionWithQuerier(ctx, cfg, telem.Logger, mockDb, mockItemQuerier)
	pegomock.When(
		mockItemQuerier.QueryItemsAsyncBatch(ctx, telem.Logger, queryWithLimit, "partitionKey"),
	).ThenReturn(itemsCh, errCh)

	g, _ := errgroup.WithContext(ctx)
	g.Go(func() error {
		return transition.Run(false, "partitionKey", 10, 1)
	})

	itemsCh <- []*models.Item{item1, item2}
	close(itemsCh)
	close(errCh)

	err := g.Wait()
	assert.NoError(t, err)

	options := &interfaces.QueryOptions{RetryCount: 10}
	inOrderContext := new(pegomock.InOrderContext)
	mockDb.VerifyWasCalledInOrder(pegomock.Once(), inOrderContext).DeleteWithOptions(pegomock.Any[context.Context](), pegomock.Eq(telem.Logger), pegomock.Eq(&key1), pegomock.Eq(options))
	mockDb.VerifyWasCalledInOrder(pegomock.Once(), inOrderContext).DeleteWithOptions(pegomock.Any[context.Context](), pegomock.Eq(telem.Logger), pegomock.Eq(&key2), pegomock.Eq(options))
}

func TestDeletePartitionDataTransition_Run_WithNoData(t *testing.T) {
	cfg := &config.Config{
		Environment: "test",
	}

	ctx := context.Background()
	telem, _ := telemetry.NewFromEnv()

	mocker := pegomock.WithT(t)
	mockDb := fakes.NewMockDatabase(mocker)
	mockItemQuerier := fakes.NewMockModelQuerier[*models.Item](mocker)

	itemsCh := make(chan []*models.Item)
	errCh := make(chan error)

	queryWithLimit := fmt.Sprintf("SELECT * FROM c OFFSET 0 LIMIT %d", 10)
	transition := NewDeletePartitionDataTransitionWithQuerier(ctx, cfg, telem.Logger, mockDb, mockItemQuerier)
	pegomock.When(
		mockItemQuerier.QueryItemsAsyncBatch(ctx, telem.Logger, queryWithLimit, "partitionKey"),
	).ThenReturn(itemsCh, errCh)

	g, _ := errgroup.WithContext(ctx)
	g.Go(func() error {
		return transition.Run(false, "partitionKey", 10, 1)
	})

	close(itemsCh)
	close(errCh)

	err := g.Wait()
	assert.NoError(t, err)

	inOrderContext := new(pegomock.InOrderContext)
	mockDb.VerifyWasCalledInOrder(pegomock.Never(), inOrderContext).DeleteWithOptions(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[models.ItemKey](), pegomock.Any[*interfaces.QueryOptions]())
}

func TestDeletePartitionDataTransition_Run_WithErrorQuerying(t *testing.T) {
	cfg := &config.Config{
		Environment: "test",
	}

	ctx := context.Background()
	telem, _ := telemetry.NewFromEnv()

	mocker := pegomock.WithT(t)
	mockDb := fakes.NewMockDatabase(mocker)
	mockItemQuerier := fakes.NewMockModelQuerier[*models.Item](mocker)

	itemsCh := make(chan []*models.Item)
	errCh := make(chan error)

	queryWithLimit := fmt.Sprintf("SELECT * FROM c OFFSET 0 LIMIT %d", 10)
	transition := NewDeletePartitionDataTransitionWithQuerier(ctx, cfg, telem.Logger, mockDb, mockItemQuerier)
	pegomock.When(
		mockItemQuerier.QueryItemsAsyncBatch(ctx, telem.Logger, queryWithLimit, "partitionKey"),
	).ThenReturn(itemsCh, errCh)

	g, _ := errgroup.WithContext(ctx)
	g.Go(func() error {
		return transition.Run(false, "partitionKey", 10, 1)
	})

	close(itemsCh)
	errCh <- errors.New("Boom!")
	close(errCh)

	err := g.Wait()
	assert.ErrorContains(t, err, "failed to query items: Boom!")

	inOrderContext := new(pegomock.InOrderContext)
	mockDb.VerifyWasCalledInOrder(pegomock.Never(), inOrderContext).DeleteWithOptions(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[models.ItemKey](), pegomock.Any[*interfaces.QueryOptions]())
}

func TestDeletePartitionDataTransition_Run_WithErrorDeleting(t *testing.T) {
	cfg := &config.Config{
		Environment: "test",
	}

	ctx := context.Background()
	telem, _ := telemetry.NewFromEnv()

	mocker := pegomock.WithT(t)
	mockDb := fakes.NewMockDatabase(mocker)
	mockItemQuerier := fakes.NewMockModelQuerier[*models.Item](mocker)

	key1 := models.Key{Id: "test1", PartitionKey: "partitionKey"}
	item1 := &models.Item{Key: key1}

	key2 := models.Key{Id: "test2", PartitionKey: "partitionKey"}
	item2 := &models.Item{Key: key2}

	key3 := models.Key{Id: "test3", PartitionKey: "partitionKey"}
	item3 := &models.Item{Key: key3}

	itemsCh := make(chan []*models.Item)
	errCh := make(chan error)

	queryWithLimit := fmt.Sprintf("SELECT * FROM c OFFSET 0 LIMIT %d", 10)
	transition := NewDeletePartitionDataTransitionWithQuerier(ctx, cfg, telem.Logger, mockDb, mockItemQuerier)
	pegomock.When(
		mockItemQuerier.QueryItemsAsyncBatch(ctx, telem.Logger, queryWithLimit, "partitionKey"),
	).ThenReturn(itemsCh, errCh)

	options := &interfaces.QueryOptions{RetryCount: 10}
	pegomock.When(
		mockDb.DeleteWithOptions(pegomock.Any[context.Context](), pegomock.Eq(telem.Logger), pegomock.Eq(&key2), pegomock.Eq(options)),
	).ThenReturn(errors.New("Boom!"))

	g, _ := errgroup.WithContext(ctx)
	g.Go(func() error {
		return transition.Run(false, "partitionKey", 10, 1)
	})

	itemsCh <- []*models.Item{item1, item2, item3}
	close(itemsCh)
	close(errCh)

	err := g.Wait()
	assert.NoError(t, err)

	inOrderContext := new(pegomock.InOrderContext)
	mockDb.VerifyWasCalledInOrder(pegomock.Once(), inOrderContext).DeleteWithOptions(pegomock.Any[context.Context](), pegomock.Eq(telem.Logger), pegomock.Eq(&key1), pegomock.Eq(options))
	mockDb.VerifyWasCalledInOrder(pegomock.Once(), inOrderContext).DeleteWithOptions(pegomock.Any[context.Context](), pegomock.Eq(telem.Logger), pegomock.Eq(&key2), pegomock.Eq(options))
	mockDb.VerifyWasCalledInOrder(pegomock.Never(), inOrderContext).DeleteWithOptions(pegomock.Any[context.Context](), pegomock.Eq(telem.Logger), pegomock.Eq(&key3), pegomock.Eq(options))
}

func TestDeletePartitionDataTransition_DryRun(t *testing.T) {
	cfg := &config.Config{
		Environment: "test",
	}

	ctx := context.Background()
	telem, _ := telemetry.NewFromEnv()

	mocker := pegomock.WithT(t)
	mockDb := fakes.NewMockDatabase(mocker)
	mockItemQuerier := fakes.NewMockModelQuerier[*models.Item](mocker)

	key1 := models.Key{Id: "test1", PartitionKey: "partitionKey"}
	item1 := &models.Item{Key: key1}

	key2 := models.Key{Id: "test2", PartitionKey: "partitionKey"}
	item2 := &models.Item{Key: key2}

	itemsCh := make(chan []*models.Item)
	errCh := make(chan error)

	queryWithLimit := fmt.Sprintf("SELECT * FROM c OFFSET 0 LIMIT %d", 10)
	transition := NewDeletePartitionDataTransitionWithQuerier(ctx, cfg, telem.Logger, mockDb, mockItemQuerier)
	pegomock.When(
		mockItemQuerier.QueryItemsAsyncBatch(ctx, telem.Logger, queryWithLimit, "partitionKey"),
	).ThenReturn(itemsCh, errCh)

	g, _ := errgroup.WithContext(ctx)
	g.Go(func() error {
		return transition.Run(true, "partitionKey", 10, 1)
	})

	itemsCh <- []*models.Item{item1, item2}
	close(itemsCh)
	close(errCh)

	err := g.Wait()
	assert.NoError(t, err)

	options := &interfaces.QueryOptions{RetryCount: 10}
	inOrderContext := new(pegomock.InOrderContext)
	mockDb.VerifyWasCalledInOrder(pegomock.Never(), inOrderContext).DeleteWithOptions(ctx, telem.Logger, &key1, options)
	mockDb.VerifyWasCalledInOrder(pegomock.Never(), inOrderContext).DeleteWithOptions(ctx, telem.Logger, &key2, options)
}

func TestDeletePartitionDataTransition_Run_WithoutPartionKey(t *testing.T) {
	cfg := &config.Config{
		Environment: "test",
	}

	ctx := context.Background()
	telem, _ := telemetry.NewFromEnv()

	mocker := pegomock.WithT(t)
	mockDb := fakes.NewMockDatabase(mocker)
	mockItemQuerier := fakes.NewMockModelQuerier[*models.Item](mocker)

	transition := NewDeletePartitionDataTransitionWithQuerier(ctx, cfg, telem.Logger, mockDb, mockItemQuerier)

	err := transition.Run(false, "", 10, 1)
	assert.ErrorContains(t, err, "partition key is required")

	inOrderContext := new(pegomock.InOrderContext)
	mockDb.VerifyWasCalledInOrder(pegomock.Never(), inOrderContext).DeleteWithOptions(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[models.ItemKey](), pegomock.Any[*interfaces.QueryOptions]())
}

func TestDeletePartitionDataTransition_Run_WithNegativeLimit(t *testing.T) {
	cfg := &config.Config{
		Environment: "test",
	}

	ctx := context.Background()
	telem, _ := telemetry.NewFromEnv()

	mocker := pegomock.WithT(t)
	mockDb := fakes.NewMockDatabase(mocker)
	mockItemQuerier := fakes.NewMockModelQuerier[*models.Item](mocker)

	transition := NewDeletePartitionDataTransitionWithQuerier(ctx, cfg, telem.Logger, mockDb, mockItemQuerier)

	err := transition.Run(false, "partition", -1, 1)
	assert.ErrorContains(t, err, "limit greater than zero is required")

	inOrderContext := new(pegomock.InOrderContext)
	mockDb.VerifyWasCalledInOrder(pegomock.Never(), inOrderContext).DeleteWithOptions(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[models.ItemKey](), pegomock.Any[*interfaces.QueryOptions]())
}

func TestDeletePartitionDataTransition_Run_WithNegativeRate(t *testing.T) {
	cfg := &config.Config{
		Environment: "test",
	}

	ctx := context.Background()
	telem, _ := telemetry.NewFromEnv()

	mocker := pegomock.WithT(t)
	mockDb := fakes.NewMockDatabase(mocker)
	mockItemQuerier := fakes.NewMockModelQuerier[*models.Item](mocker)

	transition := NewDeletePartitionDataTransitionWithQuerier(ctx, cfg, telem.Logger, mockDb, mockItemQuerier)

	err := transition.Run(false, "partition", 1, -1)
	assert.ErrorContains(t, err, "rate greater than zero is required")

	inOrderContext := new(pegomock.InOrderContext)
	mockDb.VerifyWasCalledInOrder(pegomock.Never(), inOrderContext).DeleteWithOptions(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[models.ItemKey](), pegomock.Any[*interfaces.QueryOptions]())
}
