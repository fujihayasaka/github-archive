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
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/trace"
)

type Creator[T models.ItemKey, TReturn any] struct {
	container interfaces.CosmosConnection
	statter   stats.Client
	tracer    trace.Tracer
}

func NewCreator[T models.ItemKey, TReturn any](database interfaces.Database) *Creator[T, TReturn] {
	return &Creator[T, TReturn]{
		container: database.GetConnection(),
		statter:   database.GetStatter(),
		tracer:    database.GetTracer(),
	}
}

func (c *Creator[T, TR]) CreateWithOptions(ctx context.Context, logger log.Logger, item T, options *interfaces.QueryOptions) (TR, error) {
	ctx, sp := c.tracer.Start(ctx, "Creator.CreateWithOptions")
	defer sp.End()

	var returnType TR
	key := (models.ItemKey)(item).GetKey()
	logger = logger.WithFields(key.GetLoggerFields()...)
	partitionKey := azcosmos.NewPartitionKeyString(key.PartitionKey)

	b, err := json.Marshal(item)
	if err != nil {
		return returnType, errors.Wrap(err, "CreateWithOptions Marshal failed")
	}

	o, retryCount := parseOptions(options)

	var returnError error
	for i := 0; i <= retryCount; i++ {
		start := time.Now()
		itemResponse, err := c.container.CreateItem(ctx, partitionKey, b, o)
		elapsed := time.Since(start)
		logger = logger.WithFields(GetItemResponseLoggerFields(itemResponse, elapsed, err)...)

		captureCosmosDBMetrics(ctx, c.statter, "create.create_with_option", key, itemResponse.RequestCharge, elapsed, err)

		// only log fist error in retry loop to reduce error noise
		if err != nil && i == 0 {
			logger.WithError(err).Error("CreateWithOptions failed")
		}

		if !ShouldRaiseError(err, options) {
			if err := json.Unmarshal(itemResponse.Value, &returnType); err != nil {
				return returnType, errors.Wrap(err, "CreateWithOptions Unmarshal failed")
			}

			logger.Info("CreateWithOptions success")
			return returnType, nil
		}

		// Don't retry on 409 errors as well, as it's a conflict it won't resolve itself
		if Is409Conflict(err) {
			return returnType, err
		}

		// Don't retry on 403 errors as well, as it's a forbidden it won't resolve itself
		// As of now we know this can happen when a partition hits the 20GB limit
		if Is403Forbidden(err) {
			return returnType, err
		}

		c.statter.Counter(
			"db.retry",
			stats.Tags{
				"type":        "create_with_options",
				"retry_count": strconv.Itoa(i + 1),
				"status_code": strconv.Itoa(GetErrorStatusCode(err)),
			},
			int64(1),
		)

		returnError = err
		utils.WaitForThrottling(i+1, false)
	}

	// Adding the partition key mostly to debug "Partition key reached maximum
	// size of 20 GB" errors. They return 403 status code on creates.
	// More context: https://github.com/github/gitcoin/issues/13664
	logger.WithError(returnError).Error("CreateWithOptions failed, retries exhausted")
	c.statter.Counter(
		"db.retries_exhausted",
		stats.Tags{
			"type":          "create_with_options",
			"status_code":   strconv.Itoa(GetErrorStatusCode(returnError)),
			"partition_key": key.PartitionKey,
		},
		int64(1),
	)

	return returnType, returnError
}
