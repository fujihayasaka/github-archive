package throttler

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/goleak"
)

type mockThrottler struct {
	canWriteFn func(ctx context.Context) (bool, error)
}

func (t *mockThrottler) CanWrite(ctx context.Context) (bool, error) {
	return t.canWriteFn(ctx)
}

func TestResultsAreCached(t *testing.T) {
	defer goleak.VerifyNone(t)

	var mu sync.Mutex
	var called int
	tt := &mockThrottler{
		canWriteFn: func(ctx context.Context) (bool, error) {
			mu.Lock()
			called++
			mu.Unlock()

			return true, nil
		},
	}
	ct := newCachingThrottler(tt, 10*time.Millisecond, log.NewNullLogger(), stats.NullStatter)

	// wait for throttler to be ready
	for i := 0; i < 20; i++ {
		if ct.ready() {
			break
		}
		time.Sleep(5 * time.Millisecond)
		t.Log("waiting for throttler to be ready...")
	}

	for i := 0; i < 5; i++ {
		writable, err := ct.CanWrite(context.Background())
		require.NoError(t, err)
		require.True(t, writable)
	}

	mu.Lock()
	assert.Equal(t, 1, called)
	mu.Unlock()

	time.Sleep(12 * time.Millisecond)
	for i := 0; i < 5; i++ {
		writable, err := ct.CanWrite(context.Background())
		require.NoError(t, err)
		require.True(t, writable)
	}
	mu.Lock()
	assert.Equal(t, 2, called)
	mu.Unlock()

	ct.Stop()
}
