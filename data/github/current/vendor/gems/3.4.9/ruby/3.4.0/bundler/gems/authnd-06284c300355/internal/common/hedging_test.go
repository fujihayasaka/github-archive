package common

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"go.uber.org/goleak"
)

type testHedgeManager struct {
	waitTime                  time.Duration
	maxHedges                 int
	handleOperationDurationFn func(time.Duration)
}

func (m testHedgeManager) GetWaitTime() time.Duration {
	return m.waitTime
}

func (m testHedgeManager) GetMaxNumberOfHedges() int {
	return m.maxHedges
}

func (m testHedgeManager) HandleOperationDuration(d time.Duration) {
	m.handleOperationDurationFn(d)
}

func TestHedging_ContextCancelled(t *testing.T) {
	defer goleak.VerifyNone(t)

	m := testHedgeManager{
		waitTime:  1 * time.Millisecond,
		maxHedges: 1,
		handleOperationDurationFn: func(d time.Duration) {
			// do nothing
		},
	}

	ready := make(chan bool)
	done := make(chan bool)

	ctx, cancel := context.WithCancel(context.Background())

	go func() {
		// primary request started
		<-ready
		// hedged request started
		<-ready
		// cancel request
		cancel()
	}()

	err := WithHedging(ctx, "test_operation", func(ctx context.Context) error {
		ready <- true
		done <- true
		return nil
	}, m)
	assert.Equal(t, err, context.Canceled)

	// ensure all request goroutines terminate
	<-done
	<-done
}
