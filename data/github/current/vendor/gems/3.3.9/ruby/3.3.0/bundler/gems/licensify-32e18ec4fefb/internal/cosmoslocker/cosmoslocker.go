// Package cosmoslocker is used to store distributed locks in cosmos
package cosmoslocker

import (
	"context"
	"encoding/json"
	"errors"
	"strconv"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/licensify/internal/cosmos"
	"github.com/github/licensify/internal/models"
	"github.com/github/licensify/internal/utils"
	"github.com/go-co-op/gocron/v2"
)

var (
	// ErrFailedToObtainLock is returned when the lock cannot be obtained
	ErrFailedToObtainLock = errors.New("gocron: failed to obtain lock")

	// ErrFailedToReleaseLock is returned when the lock cannot be released
	ErrFailedToReleaseLock = errors.New("gocron: failed to release lock")
)

// NewCosmosLocker provides an implementation of the Locker interface using
// cosmos for storage.
func NewCosmosLocker(statter stats.Client, logger log.Logger, readWriter cosmos.ReadWriter) gocron.Locker {
	return &Locker{statter: statter, logger: logger, readWriter: readWriter}
}

var _ gocron.Locker = (*Locker)(nil)

// Locker is used for making locks in cosmos
type Locker struct {
	statter    stats.Client
	logger     log.Logger
	readWriter cosmos.ReadWriter
}

// Lock makes a lock in cosmos
func (c *Locker) Lock(ctx context.Context, key string) (gocron.Lock, error) {
	k := &models.Key{
		PartitionKey: "locks",
		ID:           key,
	}

	// Leverages 409 conflicts to act as a semaphore
	partitionKey := azcosmos.NewPartitionKeyString(k.PartitionKey)

	logger := c.logger.WithFields(k.GetLoggerFields()...)

	b, err := json.Marshal(k)
	if err != nil {
		return nil, err
	}

	var returnError error
	for i := 0; i <= 20; i++ {
		err := ctx.Err()
		if err != nil {
			return nil, ErrFailedToObtainLock
		}

		start := time.Now()
		itemResponse, err := c.readWriter.CreateItem(ctx, partitionKey, b, nil)
		elapsed := time.Since(start)
		logger = logger.WithFields(cosmos.GetItemResponseLoggerFields(itemResponse, elapsed, err)...)

		// only log fist error in retry loop to reduce error noise
		if err != nil && i == 0 {
			logger.WithError(err).Error("Lock failed")
		}

		if err == nil {
			logger.Info("Lock success")

			l := &cosmosLock{
				id:         key,
				statter:    c.statter,
				logger:     c.logger,
				readWriter: c.readWriter,
			}
			return l, nil
		}

		// Don't retry on 409 errors as well, as it's a conflict it won't resolve itself
		if cosmos.Is409Conflict(err) {
			return nil, ErrFailedToObtainLock
		}

		// Don't retry on 403 errors as well, as it's a forbidden it won't resolve itself
		// As of now we know this can happen when a partition hits the 20GB limit
		if cosmos.Is403Forbidden(err) {
			return nil, ErrFailedToObtainLock
		}

		c.statter.Counter(
			"db.retry",
			stats.Tags{
				"type":        "lock",
				"retry_count": strconv.Itoa(i + 1),
				"status_code": strconv.Itoa(cosmos.GetErrorStatusCode(err)),
			},
			int64(1),
		)

		returnError = err
		utils.WaitForThrottling(i+1, true)
	}

	// Adding the partition key mostly to debug "Partition key reached maximum
	// size of 20 GB" errors. They return 403 status code on creates.
	// More context: https://github.com/github/gitcoin/issues/13664
	logger.WithError(returnError).Error("CreateWithOptions failed, retries exhausted")
	c.statter.Counter(
		"db.retries_exhausted",
		stats.Tags{
			"type":          "lock",
			"status_code":   strconv.Itoa(cosmos.GetErrorStatusCode(returnError)),
			"partition_key": k.PartitionKey,
		},
		int64(1),
	)

	return nil, ErrFailedToObtainLock
}

var _ gocron.Lock = (*cosmosLock)(nil)

type cosmosLock struct {
	id         string
	statter    stats.Client
	logger     log.Logger
	readWriter cosmos.ReadWriter
}

// release a lock in cosmos
func (r *cosmosLock) Unlock(ctx context.Context) error {
	// Sleep for 5 seconds to ensure a minimum amount of locked time.
	time.Sleep(5 * time.Second)

	k := &models.Key{
		PartitionKey: "locks",
		ID:           r.id,
	}

	// The interface requires a ctx param, but we don't want to use that context
	// in the event we're attempting to gracefully shutdown. Otherwise, the delete will
	// fail due to a cancelling context.
	bkgctx := context.Background()

	partitionKey := azcosmos.NewPartitionKeyString(k.PartitionKey)

	logger := r.logger.WithFields(k.GetLoggerFields()...)

	var returnError error
	for i := 0; i <= 20; i++ {
		err := bkgctx.Err()
		if err != nil {
			return ErrFailedToReleaseLock
		}

		start := time.Now()
		//nolint:contextcheck // This needs to use the background context, as explained above
		itemResponse, err := r.readWriter.DeleteItem(bkgctx, partitionKey, k.ID, nil)
		elapsed := time.Since(start)
		logger = logger.WithFields(cosmos.GetItemResponseLoggerFields(itemResponse, elapsed, err)...)

		// only log fist error in retry loop to reduce error noise
		if err != nil && i == 0 {
			logger.WithError(err).Error("Unlock failed")
		}

		if err == nil {
			logger.Info("Unlock success")
			return nil
		}

		// Don't retry on 404 errors as well, as it's a not found it won't resolve itself
		if cosmos.IsNotFoundError(err) {
			return ErrFailedToReleaseLock
		}

		r.statter.Counter(
			"db.retry",
			stats.Tags{
				"type":        "unlock",
				"retry_count": strconv.Itoa(i + 1),
				"status_code": strconv.Itoa(cosmos.GetErrorStatusCode(err)),
			},
			int64(1),
		)

		returnError = err
		utils.WaitForThrottling(i+1, false)
	}

	logger.WithError(returnError).Error("Unlock failed, retries exhausted")
	r.statter.Counter(
		"db.retries_exhausted",
		stats.Tags{
			"type":        "unlock",
			"status_code": strconv.Itoa(cosmos.GetErrorStatusCode(returnError)),
		},
		int64(1),
	)

	return ErrFailedToReleaseLock
}
