// Package ps provides a simple API to report the current process statistics to
// a statsd endpoint
package ps

import (
	"context"
	"runtime"
	"time"

	"github.com/github/go-stats"
)

const defaultInterval = 5 * time.Second

// Report starts reporting the current process' statistics to the given stats
// Client.  The reported metrics are sent every `interval`. They are all
// namespaced under "proc.*".
// Deprecated: use (*Reporter).Run instead.
func Report(stats stats.Client, interval time.Duration) {
	reporter := &Reporter{
		Stats:    stats,
		Interval: interval,
	}
	go func() {
		_ = reporter.Run(context.Background())
	}()
}

// Reporter is a helper struct to periodically report the current process' metrics
// to the given stats client.
type Reporter struct {
	Stats    stats.Client
	Interval time.Duration

	// Tags represents the tags to be included with each report. This is
	// optional and can be used to add additional information.
	Tags stats.Tags

	// GC pause time in the last report, to measure pauses/s
	lastPauseNs uint64
}

// Run runs the reporting loop and blocks until the given context is cancelled.
func (r *Reporter) Run(ctx context.Context) error {
	if r.Interval == 0 {
		r.Interval = defaultInterval
	}
	tick := time.NewTicker(r.Interval)
	defer tick.Stop()

	for {
		select {
		case <-tick.C:
			r.Report()
		case <-ctx.Done():
			return nil
		}
	}
}

// Report reports all current process statistics to the stats client.
// This method is periodically called by (*Reporter).Run, but it may be
// called manually if you don't want a full reporting loop running.
func (r *Reporter) Report() {
	if r.Interval == 0 {
		r.Interval = defaultInterval
	}

	var memStats runtime.MemStats
	runtime.ReadMemStats(&memStats)

	r.Stats.Gauge("proc.goroutines", r.Tags, int64(runtime.NumGoroutine()))                                           //nolint:gosec // Number of goroutinesdoes not realistically overflow int64
	r.Stats.Gauge("proc.memory.allocated", r.Tags, int64(memStats.Alloc))                                             //nolint:gosec // Allocated memory does not realistically overflow int64
	r.Stats.Gauge("proc.memory.mallocs", r.Tags, int64(memStats.Mallocs))                                             //nolint:gosec // Number of mallocs does not realistically overflow int64
	r.Stats.Gauge("proc.memory.frees", r.Tags, int64(memStats.Frees))                                                 //nolint:gosec // Number of frees does not realistically overflow int64
	r.Stats.Gauge("proc.memory.gc.total_pause", r.Tags, int64(time.Duration(memStats.PauseTotalNs)/time.Millisecond)) //nolint:gosec // Pause time does not realistically overflow int64
	r.Stats.Gauge("proc.memory.heap", r.Tags, int64(memStats.HeapAlloc))                                              //nolint:gosec // Heap size does not realistically overflow int64
	r.Stats.Gauge("proc.memory.stack", r.Tags, int64(memStats.StackInuse))                                            //nolint:gosec // Stack size does not realistically overflow int64

	if r.lastPauseNs > 0 {
		pauseSinceLastSample := int64(memStats.PauseTotalNs - r.lastPauseNs) //nolint:gosec // Time difference does not realistically overflow int64
		r.Stats.Gauge("proc.memory.gc.pause_per_second", nil,
			pauseSinceLastSample/int64(time.Millisecond)/int64(r.Interval.Seconds()))
	}

	r.lastPauseNs = memStats.PauseTotalNs
}
