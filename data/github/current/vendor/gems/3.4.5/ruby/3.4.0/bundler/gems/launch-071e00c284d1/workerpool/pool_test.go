package workerpool

import (
	"context"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
)

func Test_pool_ShutdownWaitsForAllQueuedJobs(t *testing.T) {
	var (
		jobs    = 10
		workers = 3
	)

	pool := NewPool(workers, jobs, logger.TestLogger(), statter.NullStatter())
	ctx := context.Background()

	calls := int32(0)
	jobsCanFinish := make(chan struct{})

	for i := 0; i < jobs; i++ {
		require.NoError(t, pool.Run(ctx, "test", func(context.Context) error {
			<-jobsCanFinish
			atomic.AddInt32(&calls, 1)
			return nil
		}))
	}

	stopped := make(chan struct{})
	go func() {
		pool.Stop()
		close(stopped)
	}()

	assert.Equal(t, int32(0), atomic.LoadInt32(&calls), "Expect jobs to be pending still")

	close(jobsCanFinish)
	<-stopped

	assert.Equal(t, int32(jobs), atomic.LoadInt32(&calls), "Expect jobs to be pending still")
}

func Test_pool_RunAfterShutdown(t *testing.T) {
	pool := NewPool(1, 1, logger.TestLogger(), statter.NullStatter())
	pool.Stop()
	assert.NotPanics(t, func() {
		err := pool.Run(context.Background(), "boom", func(context.Context) error { return nil })
		assert.EqualError(t, err, "Worker pool has been stopped")
	})
}

func Test_pool_PeriodicallyWithShutdown(t *testing.T) {
	calls := int32(0)

	pool := NewPool(1, 1, logger.NullLogger(), statter.NullStatter())
	pool.Periodically(10*time.Millisecond, "test", func(context.Context) error {
		atomic.AddInt32(&calls, 1)
		return nil
	})

	time.Sleep(50 * time.Millisecond)

	pool.Stop()
	actualCalls := atomic.LoadInt32(&calls)
	assert.NotEqual(t, int32(0), actualCalls, "Expect some calls")
	assert.NotEqual(t, int32(1), actualCalls, "Expect some calls")
	time.Sleep(50 * time.Millisecond)
	assert.Equal(t, actualCalls, atomic.LoadInt32(&calls), "Expect no more calls")
}

func Test_pool_PeriodicallyWithShutdownAndSlowJob(t *testing.T) {
	calls := int32(0)
	ctx := context.Background()

	pool := NewPool(1, 10, logger.NullLogger(), statter.NullStatter())
	require.NoError(t, pool.Run(ctx, "slow", func(context.Context) error {
		time.Sleep(60 * time.Millisecond)
		return nil
	}))

	pool.Periodically(10*time.Millisecond, "test", func(context.Context) error {
		atomic.AddInt32(&calls, 1)
		return nil
	})

	time.Sleep(50 * time.Millisecond)
	pool.Stop()

	actualCalls := atomic.LoadInt32(&calls)
	assert.Equal(t, int32(0), actualCalls, "Expect no calls yet")
	time.Sleep(50 * time.Millisecond)
	assert.Equal(t, actualCalls, atomic.LoadInt32(&calls), "Expect no calls after shutdown")
}
