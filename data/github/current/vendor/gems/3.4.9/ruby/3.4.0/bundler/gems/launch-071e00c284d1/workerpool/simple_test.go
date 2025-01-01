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
	"github.com/github/launch/utils/testutils"
)

func Test_simple_ShutdownWaitsForThreads(t *testing.T) {
	var pool Workers = NewSimple(logger.NullLogger(), statter.NullStatter())
	ctx := context.Background()

	calls := int32(0)
	jobsCanFinish := make(chan struct{})

	for i := 0; i < 2; i++ {
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

	assert.Equal(t, int32(2), atomic.LoadInt32(&calls), "Expect jobs to be done")
}

func Test_simple_PeriodicallyWithShutdown(t *testing.T) {
	calls := int32(0)

	var pool Workers = NewSimple(logger.NullLogger(), statter.NullStatter())
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

func Test_simple_JobCtx(t *testing.T) {
	ctx := context.Background()

	pool := NewSimple(logger.NullLogger(), statter.NullStatter())

	sns := testutils.CollectFinishedSpanNames(func() {
		pool.RunNonBlocking(ctx, "test", func(ctx context.Context) error {
			return nil
		})

		pool.Stop()
	})

	expectedNames := []string{"workerpool/(*Simple).Simple.Run.test", "workerpool/_run"}
	assert.ElementsMatch(t, sns, expectedNames)
}

func init() {
	testutils.EnsureGlobalTracerIsMocked()
}
