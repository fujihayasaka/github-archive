// See mock.go for why we have our own clock package.
package clock

import "time"

// Our clock interfaces, allowing for mocking.
type Clock interface {
	Now() time.Time
	Since(t time.Time) time.Duration

	// NewTicker creates a new ticker.
	// You have to call `Stop` to release resources
	NewTicker(d time.Duration) Ticker
}

type Ticker interface {
	C() <-chan time.Time

	Stop()
}

// wrappers around time's implementations.
type clock struct{}

func New() Clock {
	return &clock{}
}

func (c *clock) Now() time.Time {
	return time.Now().UTC()
}

func (c *clock) Since(t time.Time) time.Duration {
	return time.Since(t)
}

func (c *clock) NewTicker(d time.Duration) Ticker {
	return &ticker{
		tt: time.NewTicker(d),
	}
}

type ticker struct {
	tt *time.Ticker
}

func (t *ticker) C() <-chan time.Time {
	return t.tt.C
}

func (t *ticker) Stop() {
	t.tt.Stop()
}
