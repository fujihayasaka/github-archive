package repolocks

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/segmentio/ksuid"
)

type Lock interface {
	fmt.Stringer
	Name() string
	ID() string
	ExpiresAt() time.Time
	ReLock(ctx context.Context) error
	NotifyUnlocked() <-chan bool
	Unlock()
	IsValid() bool
	IsExpired() bool
	IsLocked() bool
	StartRelocker(ctx context.Context) context.Context
}

var _ Lock = &repoLock{}

type repoLock struct {
	repoID       uint64
	name         string
	id           ksuid.KSUID
	expireAt     time.Time
	lockDuration time.Duration
	mut          sync.RWMutex // Prevents unlock/relock from tripping over each other
	relock       func(ctx context.Context) error
	unlockOnce   sync.Once
	unlock       func()
	unlockChan   chan bool
}

func (l *repoLock) String() string {
	return fmt.Sprintf("Lock {Repo: %d Name: %q locked: %v: LockID: %q Expires: %v}", l.repoID, l.name, l.IsLocked(), l.id.String(), l.expireAt)
}

func (l *repoLock) kvps() []kvp.Field {
	return []kvp.Field{
		kvp.Uint64("lock_repo_id", l.repoID),
		kvp.String("lock_name", l.name),
		kvp.String("lock_id", l.id.String()),
		kvp.Duration("lock_duration", l.lockDuration),
		kvp.Time("lock_expires_at", l.ExpiresAt()),
	}
}

func (l *repoLock) Name() string {
	return l.name
}

func (l *repoLock) ID() string {
	l.mut.RLock()
	defer l.mut.RUnlock()
	return l.id.String()
}

func (l *repoLock) ExpiresAt() time.Time {
	l.mut.RLock()
	defer l.mut.RUnlock()
	return l.expireAt
}

func (l *repoLock) ReLock(ctx context.Context) error {
	return l.relock(ctx)
}

func (l *repoLock) NotifyUnlocked() <-chan bool {
	return l.unlockChan
}

func (l *repoLock) Unlock() {
	if l.unlock == nil {
		return
	}
	l.unlock()
}

func (l *repoLock) IsValid() bool {
	l.mut.RLock()
	defer l.mut.RUnlock()
	return !l.id.IsNil()
}

func (l *repoLock) IsExpired() bool {
	return l.ExpiresAt().Before(time.Now())
}

func (l *repoLock) IsLocked() bool {
	return l.IsValid() && !l.IsExpired()
}

// StartRelocker spins up a goroutine that will automatically re-lock the row when it reaches 80% of
// the requested lock duration.  The returned context will be cancelled if the lock is lost, so that further processing
// can be notified the lock is no longer relevant.
func (l *repoLock) StartRelocker(ctx context.Context) context.Context {
	ctx, cancel := context.WithCancel(ctx)
	go func() {
		defer cancel()

		ticker := time.NewTicker(l.lockDuration / 100 * 80)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-l.NotifyUnlocked():
				return
			case <-ticker.C:
				err := l.ReLock(ctx)
				if err != nil {
					contextlogger.Error(ctx, "couldn't re-acquire lock", append(l.kvps(), kvp.String("error", err.Error()))...)
					l.Unlock()
					return
				}
			}
		}
	}()
	return ctx
}
