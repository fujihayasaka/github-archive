package workflowinvoker

import (
	"time"

	"github.com/github/launch/utils/clock"
)

type testBackoffTimer struct {
	Clock *clock.Mock
	c     chan time.Time
}

// Create a new mock exponential backoff timer
func NewTestBackoffTimer(clock *clock.Mock) *testBackoffTimer {
	return &testBackoffTimer{
		Clock: clock,
		c:     make(chan time.Time, 1),
	}
}

// Start starts the timer to fire after the given duration
func (t *testBackoffTimer) Start(duration time.Duration) {
	t.Clock.Add(duration)

	select {
	case t.c <- t.Clock.Now():
	default:
	}
}

// Stop is called when the timer is not used anymore and resources may be freed.
func (t *testBackoffTimer) Stop() {
	// the standard library's (*Timer).Stop doesn't close the channel, so neither will we.
}

// C returns the timers channel which receives the current time when the timer fires.
func (t *testBackoffTimer) C() <-chan time.Time {
	return t.c
}
