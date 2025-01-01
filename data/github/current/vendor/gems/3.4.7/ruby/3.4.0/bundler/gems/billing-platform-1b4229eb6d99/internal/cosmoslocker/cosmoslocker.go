package cosmoslocker

import (
	"context"
	"time"

	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/feature-management-client-go/vexi"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/go-co-op/gocron"
)

// NewCosmosLocker provides an implementation of the Locker interface using
// cosmos for storage.
func NewCosmosLocker(d interfaces.Database, logger log.Logger, autoExpireLocksAfter time.Duration, flagger *vexi.Client) gocron.Locker {
	return &Locker{db: d, logger: logger, autoExpireLocksAfter: autoExpireLocksAfter, flagger: flagger}
}

var _ gocron.Locker = (*Locker)(nil)

type Locker struct {
	db                   interfaces.Database
	logger               log.Logger
	autoExpireLocksAfter time.Duration
	flagger              *vexi.Client
}

type cronLock struct {
	id     string
	db     interfaces.Database
	logger log.Logger
}

type cosmosLock struct {
	*models.Key
	Timestamp int64 `json:"_ts"`
}

var _ gocron.Lock = (*cronLock)(nil)

func (c *Locker) Lock(ctx context.Context, key string) (gocron.Lock, error) {
	k := &models.Key{
		PartitionKey: "locks",
		Id:           key,
	}

	// Leverages 409 conflicts to act as a semaphore
	created, err := c.db.CreateIfNotExists(ctx, c.logger, k)

	if (err != nil) || !created {
		// The lock was not created, so we need to check if it's expired
		querier := db.NewQuerier[*cosmosLock](c.db)
		cosmosLock, err := querier.ReadItem(ctx, c.logger, k, nil)
		if err != nil || cosmosLock == nil {
			return nil, gocron.ErrFailedToObtainLock
		}

		if time.Since(time.Unix(cosmosLock.Timestamp, 0)) > c.autoExpireLocksAfter {
			// The lock is expired, try to delete it and create a new one
			c.logger.Info("deleting expired lock", kvp.String("key", k.Id))
			_ = c.db.DeleteWithOptions(ctx, c.logger, k, nil)
			created, err = c.db.CreateIfNotExists(ctx, c.logger, k)
			if err != nil || !created {
				return nil, gocron.ErrFailedToObtainLock
			}
		} else {
			// Lock is still valid
			return nil, gocron.ErrFailedToObtainLock
		}
	}

	l := &cronLock{
		id:     k.Id,
		db:     c.db,
		logger: c.logger,
	}
	return l, nil
}

func (r *cronLock) Unlock(ctx context.Context) error {
	k := &models.Key{
		PartitionKey: "locks",
		Id:           r.id,
	}

	// The interface requires a ctx param, but we don't want to use that context
	// in the event we're attempting to gracefully shutdown. Otherwise, the delete will
	// fail due to a cancelling context.
	err := r.db.DeleteWithOptions(context.Background(), r.logger, k, nil)

	if err != nil {
		return gocron.ErrFailedToReleaseLock
	}
	return nil
}
