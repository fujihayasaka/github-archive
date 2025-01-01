package repolocks

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/db"
	"github.com/github/dependency-snapshots-api/internal/repolocks/internal/models"
	"github.com/segmentio/ksuid"
)

var ErrAlreadyLocked = errors.New("repository is already locked")
var ErrAlreadyUnlocked = errors.New("lock is already unlocked")
var ErrExpired = errors.New("lock is expired")

type Service interface {
	// Lock a repository for a specific function using lockName.  lockDuration is meant as a fallback only if something catastrophic occurs -
	// normal behavior will be for unlock to be explicitly called.
	Lock(ctx context.Context, repoID uint64, lockName string, lockDuration time.Duration) (Lock, error)

	// WaitLock attempts to acquire a lock, if the lock is successful it returns a Lock immediately.  If a lock is not available, it
	// will continue to attempt to acquire the lock, until the lock is successfully acquired, or waitDuration has elapsed.  If the lock is not able
	// to be acquired within waitDuration, ErrAlreadyLocked is returned.
	WaitLock(ctx context.Context, waitDuration time.Duration, repoID uint64, lockName string, lockDuration time.Duration) (Lock, error)
}

var _ Service = &lockSvc{}

type lockSvc struct {
	db               *db.DB
	primary, replica models.Querier
	logger           log.Logger
	statter          stats.Client
}

func NewService(db *db.DB, logger log.Logger, statter stats.Client) Service {
	return &lockSvc{
		db:      db,
		primary: models.New(db.PrimaryExecutor),
		replica: models.New(db.ReplicaExecutor),
		logger:  logger,
		statter: statter,
	}
}

func (l *lockSvc) Lock(ctx context.Context, repoID uint64, lockName string, lockDuration time.Duration) (Lock, error) {
	getLockParams := models.GetLockParams{RepositoryID: repoID, LockName: lockName}
	contextlogger.Info(ctx, "Calling lockSvc.Lock", kvp.Uint64("args.repoID", repoID), kvp.String("args.lockName", lockName))
	dbLock, err := l.replica.GetLock(ctx, getLockParams)
	if err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			return nil, err
		}

		contextlogger.Info(ctx, "No lock found, creating lock")

		if err := l.primary.CreateLock(ctx, models.CreateLockParams{RepositoryID: repoID, LockName: lockName}); err != nil {
			return nil, err
		}
	}

	existingLock, err := newLockFromRow(repoID, lockName, dbLock)
	if err != nil {
		return nil, err
	}

	if existingLock.IsLocked() {
		return nil, ErrAlreadyLocked
	}

	if existingLock.IsValid() && existingLock.IsExpired() {
		contextlogger.Info(ctx, "Existing lock is expired, unlocking")
		if err := l.primary.UnlockExpired(ctx, models.UnlockExpiredParams{
			RepositoryID: repoID,
			LockName:     lockName,
		}); err != nil {
			return nil, fmt.Errorf("errored when trying to unlock an expired record %s: %w", existingLock, err)
		}
	}

	dbLock.ExpireAt = sql.NullTime{
		Valid: true,
		Time:  time.Now().Add(lockDuration),
	}
	dbLock.LockID = sql.NullString{
		Valid:  true,
		String: ksuid.New().String(),
	}

	contextlogger.Info(ctx, "Locking")
	rc, err := l.primary.Lock(ctx, models.LockParams{
		RepositoryID: repoID,
		LockName:     lockName,
		LockID:       dbLock.LockID,
		ExpireAt:     dbLock.ExpireAt,
	})
	if err != nil {
		return nil, err
	}

	if rc == 0 {
		return nil, ErrAlreadyLocked
	}

	out, err := newLockFromRow(repoID, lockName, dbLock)
	if err != nil {
		return nil, err
	}

	l.setRelockFunc(out)
	l.setUnlock(out)
	out.unlockChan = make(chan bool)
	out.lockDuration = lockDuration
	l.statter.Counter("repolocks.lock", nil, 1)
	return out, nil
}

func (l *lockSvc) WaitLock(ctx context.Context, waitDuration time.Duration, repoID uint64, lockName string, lockDuration time.Duration) (Lock, error) {
	start := time.Now()
	attempts := 1
	defer func() {
		// captures how often we get the lock on the first try
		l.statter.Distribution("repolocks.waitlock.attempts", nil, float64(attempts))
	}()

	// if the lock is acquired on the first attempt, return early.
	if lock, err := l.Lock(ctx, repoID, lockName, lockDuration); err == nil {
		return lock, nil
	}

	// only stat the duration of waits if we waited at least once
	defer func() {
		l.statter.DistributionMs("repolocks.waitlock.wait_duration", stats.Tags{"attempts": strconv.Itoa(attempts)}, time.Since(start))
	}()

	for time.Since(start) < waitDuration {
		attempts++
		select {
		// don't block if context has been cancelled
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(time.Second):
			// noop happy path
		}

		lock, err := l.Lock(ctx, repoID, lockName, lockDuration)
		if err == nil {
			contextlogger.Info(ctx, "Locking succeeded")
			return lock, nil
		}

		if !errors.Is(err, ErrAlreadyLocked) {
			return nil, err
		}

		contextlogger.Info(ctx, fmt.Sprintf("Already locked, retrying: %s", err), kvp.Int("attempts", attempts))
	}

	l.statter.Counter("repolocks.waitlock.wait_expired", stats.Tags{"attempts": strconv.Itoa(attempts)}, 1)

	contextlogger.Info(ctx, "WaitLock ran out of attempts, already locked")

	return nil, ErrAlreadyLocked
}

func (l *lockSvc) setRelockFunc(lock *repoLock) {
	lock.relock = func(ctx context.Context) error {
		if lock.IsExpired() {
			return fmt.Errorf("lock %s expired @ %v; current time is %v: %w", lock, lock.ExpiresAt().UTC(), time.Now().UTC(), ErrExpired)
		}
		if !lock.IsLocked() {
			return fmt.Errorf("lock %s is already unlocked - cannot re-lock @ %v: %w", lock, time.Now(), ErrAlreadyUnlocked)
		}

		lock.mut.Lock()
		defer func() {
			lock.mut.Unlock()
			l.statter.Counter("repolocks.relock", nil, 1)
		}()

		newExpiration := time.Now().Add(lock.lockDuration)
		rc, err := l.primary.ReLock(ctx, models.ReLockParams{
			RepositoryID: lock.repoID,
			LockName:     lock.name,
			LockID: sql.NullString{
				Valid:  true,
				String: lock.id.String(),
			},
			ExpireAt: sql.NullTime{
				Time:  newExpiration,
				Valid: true,
			},
		})
		if err != nil {
			return err
		}
		if rc == 1 {
			// relock worked
			lock.expireAt = newExpiration
			l.setRelockFunc(lock)
			return nil
		}

		return fmt.Errorf("relock of %s failed: %w", lock, ErrAlreadyLocked)
	}
}

func (l *lockSvc) setUnlock(lock *repoLock) {
	lock.unlock = func() {
		lock.unlockOnce.Do(func() {
			lock.mut.Lock()
			defer func() {
				lock.mut.Unlock()
				l.statter.Counter("repolocks.unlock", nil, 1)
			}()
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_, err := l.primary.Unlock(ctx, models.UnlockParams{
				RepositoryID: lock.repoID,
				LockName:     lock.name,
				LockID: sql.NullString{
					Valid:  true,
					String: lock.id.String(),
				},
			})
			if err != nil {
				l.logger.WithError(err).Error("couldn't unlock repo", lock.kvps()...)
			}
			lock.id = ksuid.Nil
			close(lock.unlockChan)
		})
	}
}

func newLockFromRow(repoID uint64, lockName string, lr *models.DsRepoLock) (*repoLock, error) {
	out := &repoLock{repoID: repoID, name: lockName}
	if lr.LockID.Valid && lr.ExpireAt.Valid {
		id, err := ksuid.Parse(lr.LockID.String)
		if err != nil {
			return nil, fmt.Errorf("non-nil lock ID %q was not a parse-able KSUID: %w", lr.LockID.String, err)
		}
		out.id = id
		out.expireAt = lr.ExpireAt.Time
	}

	return out, nil
}
