package main

import (
	"context"
	stderrors "errors"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/go-stats"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/github/turboghas/internal/mysql_dual"
	"github.com/github/turboghas/internal/resync"
	"github.com/pkg/errors"
	"github.com/simon-engledew/sqlh"
	"golang.org/x/sync/errgroup"
)

// pull attempts to pull the desired number of items from the channel, returning less when the channel is closed.
func pull[T any](items chan T, wanted int) []T {
	out := make([]T, 0, wanted)

	for item := range items {
		out = append(out, item)
		if len(out) == wanted {
			break
		}
	}

	return out
}

// push attempts to push the items given onto the channel, returning if the context is cancelled.
func push[T any](ctx context.Context, out chan T, items []T) error {
	for _, item := range items {
		select {
		case out <- item:
			continue
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	return nil
}

func uniq[T comparable]() func([]T) []T {
	seen := make(map[T]struct{}, 512)

	return func(items []T) []T {
		out := make([]T, 0, len(items))

		for _, item := range items {
			if _, ok := seen[item]; !ok {
				out = append(out, item)
				seen[item] = struct{}{}
			}
		}

		return out
	}
}

func NewShortBackOff() backoff.BackOff {
	return backoff.NewExponentialBackOff(
		backoff.WithMaxInterval(time.Minute),
		backoff.WithMaxElapsedTime(5*time.Minute),
	)
}

// syncDataWithMonolith finds records that may be out of date and then requests the latest information from the monolith
func syncDataWithMonolith(ctx context.Context, db *mysql_dual.Connection, syncer *resync.Sync, workerCount int) (err error) {
	statter := fromctx.Statter.Value(ctx)

	jobChan := make(chan func(context.Context) error)

	workers, workerCtx := errgroup.WithContext(ctx)

	// each of these goroutines will repeatedly call the monolith to fetch the latest data for each entity they are given.
	for i := 0; i < workerCount; i++ {
		workers.Go(func() error {
			for {
				select {
				case <-workerCtx.Done():
					return workerCtx.Err()
				case jobFunc := <-jobChan:
					if jobFunc == nil {
						return workerCtx.Err()
					}
					if err := fromctx.Retry(workerCtx, func() error {
						return jobFunc(workerCtx)
					}, backoff.NewExponentialBackOff(
						backoff.WithInitialInterval(30*time.Second),
						backoff.WithMaxInterval(time.Minute),
						backoff.WithMaxElapsedTime(5*time.Minute),
					)); err != nil {
						fromctx.ExceptionReporter.Report(ctx, errors.Wrap(err, "given up on sync task"), nil)
					}
				}
			}
		})
	}

	userChan := make(chan uint64)
	repoChan := make(chan uint64)
	entityChan := make(chan resync.Entity)
	largeEntityChan := make(chan resync.Entity)

	consumer, consumerCtx := errgroup.WithContext(ctx)
	consumer.Go(func() error {
		for consumerCtx.Err() == nil {
			userIDs := pull(userChan, 100)

			if len(userIDs) == 0 {
				return nil
			}

			jobChan <- func(jobCtx context.Context) error {
				return syncer.Users(jobCtx, userIDs)
			}
		}

		return consumerCtx.Err()
	})

	consumer.Go(func() error {
		for consumerCtx.Err() == nil {
			repoIDs := pull(repoChan, 80)

			if len(repoIDs) == 0 {
				return nil
			}

			jobChan <- func(jobCtx context.Context) error {
				return syncer.Repositories(jobCtx, repoIDs)
			}
		}

		return consumerCtx.Err()
	})

	consumer.Go(func() error {
		for consumerCtx.Err() == nil {
			entities := pull(entityChan, 10)

			if len(entities) == 0 {
				return nil
			}

			jobChan <- func(jobCtx context.Context) error {
				return syncer.Entities(jobCtx, entities)
			}
		}

		return consumerCtx.Err()
	})

	consumer.Go(func() error {
		for consumerCtx.Err() == nil {
			entities := pull(largeEntityChan, 1)

			if len(entities) == 0 {
				return nil
			}

			jobChan <- func(jobCtx context.Context) error {
				return syncer.Entities(jobCtx, entities)
			}
		}

		return consumerCtx.Err()
	})

	// each of these goroutines will fetch some potentially outdated rows from the database and then send the data that needs syncing to the consumers.
	producer, producerCtx := errgroup.WithContext(ctx)
	producer.Go(func() error {
		started := time.Now()
		defer func() {
			statter.Timing("sync.repositories", stats.Tags{}, time.Since(started))
		}()

		return retryInBatches(producerCtx, db, "tg_repositories", 10_000, func(ctx context.Context, start, end uint64) error {
			repoIDs, err := sqlh.Pluck[uint64](db.Replica.QueryContext(ctx, `
SELECT repository_id
  FROM tg_repositories
 WHERE updated_at < NOW() - INTERVAL 23 HOUR
   AND id BETWEEN ? AND ?`, start, end))
			if err != nil {
				return errors.Wrap(err, "failed to scan repository_id")
			}
			return push(ctx, repoChan, repoIDs)
		})
	})
	producer.Go(func() error {
		started := time.Now()
		defer func() {
			statter.Timing("sync.purchasers", stats.Tags{}, time.Since(started))
		}()

		uniqEntities := uniq[resync.Entity]()

		return retryInBatches(producerCtx, db, "tg_purchasers", 10_000, func(ctx context.Context, start, end uint64) error {
			res, err := db.Replica.QueryContext(ctx, `
SELECT tg_purchasers.entity_id, tg_purchasers.entity_type
  FROM tg_purchasers
 WHERE tg_purchasers.updated_at < NOW() - INTERVAL 23 HOUR
   AND NOT EXISTS(SELECT 1 FROM tg_entities WHERE tg_entities.entity_id = tg_purchasers.entity_id AND tg_entities.entity_type = tg_purchasers.entity_type)
   AND tg_purchasers.id BETWEEN ? AND ?`, start, end)
			if err != nil {
				return errors.Wrap(err, "failed to scan entity")
			}
			entities, err := sqlh.ScanV(res, func(v *resync.Entity, row sqlh.Row) error {
				return row.Scan(&v.ID, &v.Type)
			})
			if err != nil {
				return err
			}

			return push(ctx, largeEntityChan, uniqEntities(entities))
		})
	})
	producer.Go(func() error {
		started := time.Now()
		defer func() {
			statter.Timing("sync.users", stats.Tags{}, time.Since(started))
		}()

		return retryInBatches(producerCtx, db, "tg_users", 10_000, func(ctx context.Context, start, end uint64) error {
			// update any User records
			// repositories will keep their Owners up to date
			userIDs, err := sqlh.Pluck[uint64](db.Replica.QueryContext(ctx, `
SELECT user_id
  FROM tg_users
 WHERE updated_at < NOW() - INTERVAL 23 HOUR
   AND type = 'User'
   AND id BETWEEN ? AND ?`, start, end))
			if err != nil {
				return errors.Wrap(err, "failed to scan user_id")
			}
			return push(ctx, userChan, userIDs)
		})
	})
	producer.Go(func() error {
		started := time.Now()
		defer func() {
			statter.Timing("sync.entities", stats.Tags{}, time.Since(started))
		}()

		return retryInBatches(producerCtx, db, "tg_entities", 10_000, func(ctx context.Context, start, end uint64) error {
			res, err := db.Replica.QueryContext(ctx, `
SELECT entity_id, entity_type, json_length(user_ids) > 250 AS 'is_large'
  FROM tg_entities
 WHERE updated_at < NOW() - INTERVAL 23 HOUR
   AND id BETWEEN ? AND ?`, start, end)
			if err != nil {
				return err
			}
			items, err := sqlh.ScanV(res, func(v *struct {
				resync.Entity
				isLarge bool
			}, row sqlh.Row) error {
				return errors.Wrap(row.Scan(&v.ID, &v.Type, &v.isLarge), "failed to scan entity")
			})
			if err != nil {
				return err
			}
			for _, item := range items {
				if item.isLarge {
					select {
					case largeEntityChan <- item.Entity:
						continue
					case <-ctx.Done():
						return ctx.Err()
					}
				} else {
					select {
					case entityChan <- item.Entity:
						continue
					case <-ctx.Done():
						return ctx.Err()
					}
				}

			}
			return nil
		})
	})
	producer.Go(func() error {
		started := time.Now()
		defer func() {
			statter.Timing("sync.contributions", stats.Tags{}, time.Since(started))
		}()

		// this block looks for repositories that are referenced by contributions and have been deleted to check they have
		// not been restored
		return retryInBatches(producerCtx, db, "tg_contributions", 10_000, func(ctx context.Context, start, end uint64) error {
			contributionsGroup, ctx := errgroup.WithContext(ctx)
			if fromctx.Env.Value(ctx).IsTest() {
				// restrict concurrency when running in tests
				// when using transaction connections we can get deadlocks that do not happen in production
				contributionsGroup.SetLimit(1)
			}

			uniqUserIDs := uniq[uint64]()
			uniqRepoIDs := uniq[uint64]()

			contributionsGroup.Go(func() error {
				userIDs, err := sqlh.Pluck[uint64](db.Replica.QueryContext(ctx, `
SELECT DISTINCT user_id
  FROM tg_contributions
 WHERE MOD(DATEDIFF(NOW(), pushed_at) - 1, 7) = 0
   AND id BETWEEN ? AND ?
   AND NOT EXISTS(SELECT 1 FROM tg_users WHERE tg_users.user_id = tg_contributions.user_id)`, start, end))
				if err != nil {
					return errors.Wrap(err, "failed to scan user_id")
				}
				return push(ctx, userChan, uniqUserIDs(userIDs))
			})
			contributionsGroup.Go(func() error {
				repoIDs, err := sqlh.Pluck[uint64](db.Replica.QueryContext(ctx, `
SELECT DISTINCT repository_id
  FROM tg_contributions
 WHERE MOD(DATEDIFF(NOW(), pushed_at) - 1, 7) = 0
   AND id BETWEEN ? AND ?
   AND NOT EXISTS(SELECT 1 FROM tg_repositories WHERE tg_repositories.repository_id = tg_contributions.repository_id)`, start, end))
				if err != nil {
					return errors.Wrap(err, "failed to scan repository_id")
				}
				return push(ctx, repoChan, uniqRepoIDs(repoIDs))
			})

			return contributionsGroup.Wait()
		})
	})

	producerErr := errors.Wrap(producer.Wait(), "producer failed")

	close(repoChan)
	close(userChan)
	close(entityChan)
	close(largeEntityChan)

	consumerErr := errors.Wrap(consumer.Wait(), "consumer failed")

	close(jobChan)

	workersErr := errors.Wrap(workers.Wait(), "workers failed")

	return stderrors.Join(producerErr, consumerErr, workersErr)
}
