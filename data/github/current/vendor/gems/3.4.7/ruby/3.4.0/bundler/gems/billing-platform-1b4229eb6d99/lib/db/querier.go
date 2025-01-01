package db

import (
	"context"
	"encoding/json"
	"strconv"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/utils"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/trace"
)

type Querier[T any] struct {
	container interfaces.CosmosConnection
	statter   stats.Client
	tracer    trace.Tracer
}

type ModelQuerier[T any] interface {
	QueryItems(ctx context.Context, logger log.Logger, queryString string, partitionKey string) ([]T, error)
	QueryItemsWithOptions(ctx context.Context, logger log.Logger, query string, pk string, retryCount int, options *azcosmos.QueryOptions) ([]T, error)
	QueryItemsAsyncBatch(ctx context.Context, logger log.Logger, query string, pk string) (<-chan []T, <-chan error)
	ReadItemWithRetries(ctx context.Context, logger log.Logger, itemKey models.ItemKey) (T, error)
}

func NewQuerier[T any](database interfaces.Database) *Querier[T] {
	return &Querier[T]{
		container: database.GetConnection(),
		statter:   database.GetStatter(),
		tracer:    database.GetTracer(),
	}
}

func NewGatewayQuerier[T any](database interfaces.Database) *Querier[T] {
	return &Querier[T]{
		container: database.GetGatewayConnection(),
		statter:   database.GetStatter(),
		tracer:    database.GetTracer(),
	}
}

// QueryItems queries the database and returns all items matching the given query and partition key.
// For queries that return a large number of items, consider using QueryItemsAsync or QueryItemsAsyncBatch instead.
func (q *Querier[T]) QueryItems(ctx context.Context, logger log.Logger, query string, pk string) ([]T, error) {
	ctx, sp := q.tracer.Start(ctx, "Querier.QueryItems")
	defer sp.End()

	return q.QueryItemsWithOptions(ctx, logger, query, pk, 0, nil)
}

func (q *Querier[T]) QueryItemsWithOptions(ctx context.Context, logger log.Logger, query string, pk string, retryCount int, options *azcosmos.QueryOptions) ([]T, error) {
	allItems := make([]T, 0)
	var err error
	for i := 0; i <= retryCount; i++ {
		allItems, err = q.getQueryItems(ctx, logger, query, pk, options)
		if err != nil {
			if Is429ToManyRequests(err) {
				utils.WaitForThrottling(i+1, false)
			} else {
				return nil, err
			}
		} else {
			return allItems, err
		}
	}
	return allItems, err
}

func (q *Querier[T]) getQueryItems(ctx context.Context, logger log.Logger, query string, pk string, options *azcosmos.QueryOptions) ([]T, error) {
	var requestCharge float32
	var elapsed time.Duration
	var queryError error
	queryPager := q.container.NewQueryItemsPager(query, azcosmos.NewPartitionKeyString(pk), options)
	items := make([]T, 0)
	key := models.NewKeyFromPartitionKey(pk)

	for queryPager.More() {
		start := time.Now()
		queryResponse, err := queryPager.NextPage(ctx)
		queryError = err
		if queryError != nil {
			return nil, errors.Wrap(queryError, "QueryItems failed on paging")
		}

		if err = unmarshallQueryResponse[T](logger, queryResponse, &items); err != nil {
			return nil, err
		}
		requestCharge += queryResponse.RequestCharge
		elapsed += time.Since(start)

	}

	logger.Info("QueryItems Success",
		kvp.String("db.cosmosdb.query", query),
		kvp.String("db.cosmosdb.partition_key", pk),
		kvp.Int64("db.cosmosdb.time_elapsed", elapsed.Milliseconds()),
		kvp.Float32("db.cosmosdb.request_charge", requestCharge),
	)
	captureCosmosDBMetrics(ctx, q.statter, "query_items", key, requestCharge, elapsed, queryError)
	return items, nil

}

func unmarshallQueryResponse[T any](logger log.Logger, queryResponse azcosmos.QueryItemsResponse, items *[]T) error {
	for _, item := range queryResponse.Items {

		var itemResponseBody T
		if err := json.Unmarshal(item, &itemResponseBody); err != nil {
			return errors.Wrap(err, "QueryItems Unmarshal failed")
		}

		*items = append(*items, itemResponseBody)
	}
	return nil
}

// QueryItemsAsync queries the database and returns a channel of individual items matching the given query and partition key.
// The channels will be closed when all items have been returned or an error is encountered.
// Consider using QueryItemsAsyncBatch instead if you will be processing items in batches.
func (q *Querier[T]) QueryItemsAsync(ctx context.Context, logger log.Logger, query string, pk string) (<-chan T, <-chan error) {
	ctx, sp := q.tracer.Start(ctx, "Querier.QueryItemsAsync")

	queryPager := q.container.NewQueryItemsPager(query, azcosmos.NewPartitionKeyString(pk), nil)

	var requestCharge float32
	var elapsed time.Duration
	var queryErr error
	itemsCh := make(chan T, 1000)
	errCh := make(chan error, 1)
	key := models.NewKeyFromPartitionKey(pk)

	go func() {
		defer func() {
			close(itemsCh)
			close(errCh)
			sp.End()
			captureCosmosDBMetrics(ctx, q.statter, "query_items_async", key, requestCharge, elapsed, queryErr)
		}()
		for queryPager.More() {
			start := time.Now()
			queryResponse, err := queryPager.NextPage(ctx)
			queryErr = err
			elapsed += time.Since(start)
			requestCharge += queryResponse.RequestCharge
			if queryErr != nil {
				errCh <- queryErr
				return
			}
			for _, item := range queryResponse.Items {
				var itemResponseBody T
				if err := json.Unmarshal(item, &itemResponseBody); err != nil {
					errCh <- err
					return
				}
				itemsCh <- itemResponseBody
			}
		}

		logger.Info("QueryItemsAsync",
			kvp.String("db.cosmosdb.query", query),
			kvp.String("db.cosmosdb.partition_key", pk),
			kvp.Int64("db.cosmosdb.time_elapsed", elapsed.Milliseconds()),
			kvp.Float32("db.cosmosdb.request_charge", requestCharge),
		)
	}()

	return itemsCh, errCh
}

// QueryItemsAsyncBatch queries the database and returns a channel of batched items matching the given query and partition key.
// The channels will be closed when all items have been returned or an error is encountered.
func (q *Querier[T]) QueryItemsAsyncBatch(ctx context.Context, logger log.Logger, query string, pk string) (<-chan []T, <-chan error) {
	ctx, sp := q.tracer.Start(ctx, "Querier.QueryItemsAsyncBatch")

	itemsCh, errCh := q.QueryItemsAsync(ctx, logger, query, pk)
	batchCh := make(chan []T, 100)

	// Start a goroutine to receive items and send them in batches.
	go func() {
		defer func() {
			close(batchCh)
			sp.End()
		}()

		ticker := time.NewTicker(1 * time.Second)
		items := []T{}
		done := false

		for !done {
			select {
			case item, ok := <-itemsCh:
				// Receive items and add them to the current batch.
				// The channel will be closed if there are no more items or an error is encountered.
				if !ok {
					done = true
				} else {
					items = append(items, item)
				}
			case <-ticker.C:
				// Check if we have any items to send.
				if len(items) == 0 {
					continue
				}
				// Send the current batch of items by creating a new slice and swapping it with the current slice.
				batch := make([]T, 0, len(items))
				batch, items = items, batch
				batchCh <- batch
			}
		}

		// Stop the ticker and send the remaining items.
		ticker.Stop()
		if len(items) > 0 {
			batchCh <- items
		}
	}()

	return batchCh, errCh
}

func (q *Querier[T]) ReadItemWithRetries(ctx context.Context, logger log.Logger, key models.ItemKey) (T, error) {
	ctx, sp := q.tracer.Start(ctx, "Querier.ReadItemWithRetries")
	defer sp.End()

	return q.ReadItem(ctx, logger, key, nil)
}

func (q *Querier[T]) ReadItem(ctx context.Context, logger log.Logger, key models.ItemKey, options *interfaces.QueryOptions) (T, error) {
	ctx, sp := q.tracer.Start(ctx, "Querier.ReadItem")
	defer sp.End()

	var t T
	k := key.GetKey()
	if k.PartitionKey == "" || k.Id == "" {
		return t, nil
	}

	logger = logger.WithFields(k.GetLoggerFields()...)

	partitionKey := azcosmos.NewPartitionKeyString(k.PartitionKey)
	parsedOptions, retryCount := parseOptions(options)

	var returnError error
	for i := 0; i <= retryCount; i++ {
		if ctx.Err() != nil {
			return t, errors.Wrap(ctx.Err(), "context error")
		}

		start := time.Now()
		itemResponse, err := q.container.ReadItem(ctx, partitionKey, k.Id, parsedOptions)
		elapsed := time.Since(start)
		logger = logger.WithFields(GetItemResponseLoggerFields(itemResponse, elapsed, err)...)

		captureCosmosDBMetrics(ctx, q.statter, "read_item", k, itemResponse.RequestCharge, elapsed, err)

		// only log fist error in retry loop to reduce error noise
		if err != nil && i == 0 {
			logger.WithError(err).Error("ReadItem failed")
		}

		if err == nil {
			if err := json.Unmarshal(itemResponse.Value, &t); err != nil {
				return t, errors.Wrap(err, "ReadItem Unmarshal failed")
			}

			logger.Info("ReadItem success")
			return t, nil
		} else if Is404NotFound(err) {
			logger.Info("ReadItem not found")
			return t, nil
		}

		q.statter.Counter(
			"db.retry",
			stats.Tags{
				"type":               "read_item",
				"retry_count":        strconv.Itoa(i + 1),
				"status_code":        strconv.Itoa(GetErrorStatusCode(err)),
				"partition_template": key.GetPartitionTemplate(),
			},
			int64(1),
		)

		returnError = err
		utils.WaitForThrottling(i+1, false)
	}

	logger.WithError(returnError).Error("ReadItem failed, retries exhausted")
	q.statter.Counter(
		"db.retries_exhausted",
		stats.Tags{
			"type":        "read_item",
			"status_code": strconv.Itoa(GetErrorStatusCode(returnError)),
		},
		int64(1),
	)

	return t, returnError
}
