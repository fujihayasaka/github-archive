package tester

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/github-telemetry-go/log"
	"github.com/patrickmn/go-cache"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestTester_PreventParallelTestRuns(t *testing.T) {
	logger, err := log.NewFromConfig(log.Config{
		LogLevel:           "debug",
		LogConsoleEncoding: "console",
	})
	require.NoError(t, err)

	ctx, cancel := context.WithCancel(
		diagnostics.WithLogger(context.Background(), logger))

	tracker := new(singleRunTracker)
	done := make(chan bool)
	test := &fakeTest{
		name:       "test",
		frequency:  1 * time.Millisecond,
		timeout:    time.Minute,
		done:       done,
		runTracker: tracker,
	}

	run := make(chan time.Time)
	tester := Tester{
		tests:    []Runnable{test},
		runCache: cache.New(1*time.Hour, 1*time.Second),
		nextRun:  run,
	}

	var testerDone bool
	testerDoneCh := make(chan bool)
	go func() {
		err = tester.Run(ctx)
		testerDone = true
		testerDoneCh <- true
	}()

	t.Log("triggering run")
	// wait for tester to start
	run <- time.Time{}
	time.Sleep(3 * time.Millisecond)

	t.Log("started run")
	// verify test run #1 has started
	assert.True(t, test.IsRunning())
	runsStarted, runsComplete := test.getRunCount()
	assert.Equal(t, 1, runsStarted)
	assert.Equal(t, 0, runsComplete)

	// let test run #1 complete
	done <- true
	time.Sleep(3 * time.Millisecond)

	// verify test run #1 is complete, test run #2 has not started
	assert.False(t, test.IsRunning())
	runsStarted, runsComplete = test.getRunCount()
	assert.Equal(t, 1, runsStarted)
	assert.Equal(t, 1, runsComplete)

	// let test run #2 start
	run <- time.Time{}
	time.Sleep(3 * time.Millisecond)

	// verify test run #2 has started
	assert.True(t, test.IsRunning())
	runsStarted, runsComplete = test.getRunCount()
	assert.Equal(t, 2, runsStarted)
	assert.Equal(t, 1, runsComplete)

	// let test run #2 complete
	done <- true
	time.Sleep(3 * time.Millisecond)

	// verify test run #2 is complete
	assert.False(t, test.IsRunning())
	runsStarted, runsComplete = test.getRunCount()
	assert.Equal(t, 2, runsStarted)
	assert.Equal(t, 2, runsComplete)

	// signal tester to stop and wait
	cancel()
	select {
	case <-testerDoneCh:
		// continue
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for tester to exit")

	}

	// verify tester stops
	assert.True(t, testerDone)
	require.Error(t, err, "unexpected error running tester")
	assert.ErrorIs(t, err, context.Canceled)
}

type fakeTest struct {
	name      string
	frequency time.Duration
	timeout   time.Duration
	done      <-chan bool

	mu           sync.RWMutex
	runsStarted  int
	runsComplete int

	runTracker
}

func (t *fakeTest) Name() string {
	return t.name
}

func (t *fakeTest) Frequency() time.Duration {
	return t.frequency
}

func (t *fakeTest) Timeout() time.Duration {
	return t.timeout
}

func (t *fakeTest) Run(ctx context.Context) error {
	t.runTracker.Start()
	defer t.runTracker.Stop()

	t.mu.Lock()
	t.runsStarted++
	t.mu.Unlock()
	defer func() {
		t.mu.Lock()
		t.runsComplete++
		t.mu.Unlock()
	}()

	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-t.done:
		return nil
	}
}

// helper so test assertions don't have to deal with the mutex
func (t *fakeTest) getRunCount() (started, completed int) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	return t.runsStarted, t.runsComplete
}
