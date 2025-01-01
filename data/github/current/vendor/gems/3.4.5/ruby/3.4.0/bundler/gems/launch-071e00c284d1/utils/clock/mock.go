// An alternative to github.com/facebookgo/clock that sends ticks at a constant interval, no matter how long the test code takes to receive them.
// See https://github.com/github/launch/pull/3259#discussion_r472575731
package clock

import (
	"sync"
	"time"
)

type Mock struct {
	tickerBufferSize int
	now              time.Time
	elapsed          time.Duration
	mu               sync.Mutex
	tickers          []*MockTicker
}

var _ Clock = (*Mock)(nil)

func NewMock(tickerBufferSize int) *Mock {
	return &Mock{
		tickerBufferSize: tickerBufferSize,
		now:              time.Date(2019, 11, 13, 17, 0, 0, 0, time.UTC),
	}
}

func (m *Mock) Now() time.Time {
	m.mu.Lock()
	defer m.mu.Unlock()

	return m.now
}

func (m *Mock) Elapsed() time.Duration {
	m.mu.Lock()
	defer m.mu.Unlock()

	return m.elapsed
}

func (m *Mock) Since(t time.Time) time.Duration {
	return m.Now().Sub(t)
}

func (m *Mock) NewTicker(d time.Duration) Ticker {
	m.mu.Lock()
	defer m.mu.Unlock()

	ticker := &MockTicker{
		ch:              make(chan time.Time, m.tickerBufferSize),
		period:          d,
		timeTilNextTick: d,
	}

	m.tickers = append(m.tickers, ticker)

	return ticker
}

func (m *Mock) Add(d time.Duration) {
	m.mu.Lock()
	defer m.mu.Unlock()

	for _, ticker := range m.tickers {
		time := m.now
		remaining := d
		for remaining >= ticker.timeTilNextTick {
			time = time.Add(ticker.timeTilNextTick)
			ticker.ch <- time

			remaining -= ticker.timeTilNextTick
			ticker.timeTilNextTick = ticker.period
		}

		ticker.timeTilNextTick -= remaining
	}

	m.now = m.now.Add(d)
	m.elapsed = m.elapsed + d
}

func (m *Mock) WaitForTickerCount(count int) {
	for {
		m.mu.Lock()
		tickerCount := len(m.tickers)
		m.mu.Unlock()

		if tickerCount >= count {
			return
		}

		time.Sleep(time.Millisecond)
	}
}

// Wait for existing ticker channels to drain.
func (m *Mock) WaitForTickersToDrain() {
	m.mu.Lock()
	tickers := m.tickers
	m.mu.Unlock()

	for _, ticker := range tickers {
		for len(ticker.ch) > 0 {
			time.Sleep(time.Millisecond)
		}
	}
}

type MockTicker struct {
	ch              chan time.Time
	period          time.Duration
	timeTilNextTick time.Duration
}

func (mt *MockTicker) C() <-chan time.Time {
	return mt.ch
}

func (mt *MockTicker) Stop() {
}
