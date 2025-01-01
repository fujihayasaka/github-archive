package throttler

import (
	"context"
	"sync"
	"time"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	freno "github.com/github/go-freno-client"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

var defaultTTL = 200 * time.Millisecond

// Throttler is an interface for throttling writes to a database. Extends the
// freno.Throttler interface with a Stop() method which terminates background
// processes for eager loading of status to the cache.
type Throttler interface {
	freno.Throttler
	Stop()
}

// internal interface for testing which is queryable for its readiness
type throttler interface {
	Throttler
	ready() bool
}

// NewCachingThrottler returns a wrapped freno.Throttler which eagerly loads the replication lag
// status from Freno and caches it. This is useful for reducing the number and total latency of
// Freno requests.
func NewCachingThrottler(host, app, cluster string, logger log.Logger, statter stats.Client) Throttler {
	logger = logger.WithFields(
		kvp.String("component", "caching_throttler"),
		kvp.String("gh.authnd.db.cluster_name", cluster),
	)

	frenoThrottler := freno.NewFrenoThrottler(host, app, cluster)
	return newCachingThrottler(frenoThrottler, defaultTTL, logger, statter)
}

func newCachingThrottler(child freno.Throttler, cacheTTL time.Duration, logger log.Logger, statter stats.Client) throttler {
	done := make(chan struct{})
	t := &cachingThrottler{
		mu:      sync.RWMutex{},
		logger:  logger,
		inner:   child,
		statter: statter,
		stopFn: func() {
			close(done)
		},
	}

	go func() {
		logger.Info("starting checker goroutine", kvp.Duration("gh.authnd.cache.ttl", cacheTTL))

		// kick off an initial update
		t.update()

		// signal that status has been updated and we're ready.
		t.mu.Lock()
		t.isReady = true
		t.mu.Unlock()

		ticker := time.NewTicker(cacheTTL)
		defer ticker.Stop()

		for {
			select {
			case <-done:
				logger.Info("stopping checker goroutine")
				return
			case <-ticker.C:
				logger.Debug("checking freno status")
				t.update()
			}
		}
	}()

	return t
}

type cachingThrottler struct {
	mu       sync.RWMutex
	canWrite bool
	isReady  bool

	logger  log.Logger
	statter stats.Client
	inner   freno.Throttler
	stopFn  func()
}

func (t *cachingThrottler) CanWrite(ctx context.Context) (bool, error) {
	statter := diagnostics.Statter(ctx)

	t.mu.RLock()
	defer t.mu.RUnlock()

	if !t.canWrite {
		statter.Counter("freno.throttled", nil, 1)
	}
	return t.canWrite, nil
}

func (t *cachingThrottler) Stop() {
	t.stopFn()
}

func (t *cachingThrottler) ready() bool {
	t.mu.RLock()
	defer t.mu.RUnlock()
	return t.isReady
}

func (t *cachingThrottler) update() {
	ctx, cancel := context.WithTimeout(context.Background(), defaultTTL)
	defer cancel()

	start := time.Now()
	canWrite, err := t.inner.CanWrite(ctx)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) {
			t.statter.Counter("freno.check_timeout", nil, 1)
		} else {
			t.statter.Counter("freno.check_error", nil, 1)
		}
		t.logger.WithError(err).Info("error checking freno status")
	}
	t.statter.DistributionMs("freno.check_latency", nil, time.Since(start))

	t.mu.Lock()
	defer t.mu.Unlock()
	t.canWrite = canWrite
}
