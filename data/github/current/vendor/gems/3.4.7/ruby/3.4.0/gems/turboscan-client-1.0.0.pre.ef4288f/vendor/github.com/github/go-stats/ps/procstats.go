// Package ps provides a simple API to report the current process statistics to
// a statsd endpoint
package ps

import (
	"context"
	"runtime"
	"runtime/debug"
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
	Stats        stats.Client
	runtimeStats stats.Client
	Interval     time.Duration

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

	// the runtime.go.* metrics should not be prefixed. This creates a copy of the stats object without a prefix.
	if r.runtimeStats == nil {
		r.runtimeStats = r.Stats.SetPrefix("")
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
	var gcStats = debug.GCStats{
		// if len(stats.PauseQuantiles) is 5, it will be filled with min, 25p, 50p, 75p, max data.
		// See [debug.ReadGCStats] for details
		PauseQuantiles: make([]time.Duration, 5),
	}

	runtime.ReadMemStats(&memStats)
	debug.ReadGCStats(&gcStats)

	r.Stats.Gauge("proc.goroutines", r.Tags, int64(runtime.NumGoroutine()))                                           //nolint:gosec // Number of goroutines does not realistically overflow int64
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

	// Report runtime.go.* metrics.
	// Based on https://github.com/DataDog/dd-trace-go/blob/98feb67c/ddtrace/tracer/metrics.go
	//
	// CPU statistics
	r.runtimeStats.Gauge("runtime.go.num_cpu", r.Tags, int64(runtime.NumCPU()))             //nolint:gosec // Number of cpu cores does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.num_goroutine", r.Tags, int64(runtime.NumGoroutine())) //nolint:gosec // Number of goroutines does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.num_cgo_call", r.Tags, runtime.NumCgoCall())

	// General statistics
	r.runtimeStats.Gauge("runtime.go.mem_stats.alloc", r.Tags, int64(memStats.Alloc))            //nolint:gosec // Allocated heap objects in bytes does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.total_alloc", r.Tags, int64(memStats.TotalAlloc)) //nolint:gosec // Total allocated heap bytes does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.sys", r.Tags, int64(memStats.Sys))                //nolint:gosec // Total system memory in bytes does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.lookups", r.Tags, int64(memStats.Lookups))        //nolint:gosec // Total number of pointer lookups does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.mallocs", r.Tags, int64(memStats.Mallocs))        //nolint:gosec // Total allocated heap objects does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.frees", r.Tags, int64(memStats.Frees))            //nolint:gosec // Total freed heap objects does not realistically overflow int64

	// Heap memory statistics
	r.runtimeStats.Gauge("runtime.go.mem_stats.heap_alloc", r.Tags, int64(memStats.HeapAlloc))       //nolint:gosec // Total heap memory in-use in bytes does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.heap_sys", r.Tags, int64(memStats.HeapSys))           //nolint:gosec // Total heap memory obtained from the OS in bytes does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.heap_idle", r.Tags, int64(memStats.HeapIdle))         //nolint:gosec // Total heap memory in idle spans in bytes does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.heap_inuse", r.Tags, int64(memStats.HeapInuse))       //nolint:gosec // Total heap memory in-use in bytes does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.heap_released", r.Tags, int64(memStats.HeapReleased)) //nolint:gosec // Total heap memory released to the OS in bytes does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.heap_objects", r.Tags, int64(memStats.HeapObjects))   //nolint:gosec // Total heap objects does not realistically overflow int64

	// Stack memory statistics
	r.runtimeStats.Gauge("runtime.go.mem_stats.stack_inuse", r.Tags, int64(memStats.StackInuse)) //nolint:gosec // Total stack memory in-use in bytes does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.stack_sys", r.Tags, int64(memStats.StackSys))     //nolint:gosec // Total stack memory obtained from the OS in bytes does not realistically overflow int64

	// Off-heap memory statistics
	r.runtimeStats.Gauge("runtime.go.mem_stats.m_span_inuse", r.Tags, int64(memStats.MSpanInuse))   //nolint:gosec // Total mspan memory in-use in bytes does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.m_span_sys", r.Tags, int64(memStats.MSpanSys))       //nolint:gosec // Total mspan memory obtained from the OS in bytes does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.m_cache_inuse", r.Tags, int64(memStats.MCacheInuse)) //nolint:gosec // Total mcache memory in-use in bytes does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.m_cache_sys", r.Tags, int64(memStats.MCacheSys))     //nolint:gosec // Total mcache memory obtained from the OS in bytes does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.buck_hash_sys", r.Tags, int64(memStats.BuckHashSys)) //nolint:gosec // Total memory used by the profiling bucket hash table in bytes does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.gc_sys", r.Tags, int64(memStats.GCSys))              //nolint:gosec // Total memory used for garbage collection metadata in bytes does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.other_sys", r.Tags, int64(memStats.OtherSys))        //nolint:gosec // Total system memory not in the heap, stack, or other memory does not realistically overflow int64

	// Garbage collector statistics
	r.runtimeStats.Gauge("runtime.go.mem_stats.next_gc", r.Tags, int64(memStats.NextGC))              //nolint:gosec // Target heap size for the next GC cycle in bytes does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.last_gc", r.Tags, int64(memStats.LastGC))              //nolint:gosec // Time of the last garbage collection, in nanoseconds since 1970 (the UNIX epoch) does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.pause_total_ns", r.Tags, int64(memStats.PauseTotalNs)) //nolint:gosec // Pause time does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.num_gc", r.Tags, int64(memStats.NumGC))                //nolint:gosec // Number of completed GC cycles does not realistically overflow int64
	r.runtimeStats.Gauge("runtime.go.mem_stats.num_forced_gc", r.Tags, int64(memStats.NumForcedGC))   //nolint:gosec // Number of forced GC cycles does not realistically overflow int64

	for i, p := range []string{"min", "25p", "50p", "75p", "max"} {
		r.runtimeStats.Gauge("runtime.go.gc_stats.pause_quantiles."+p, r.Tags, int64(gcStats.PauseQuantiles[i]))
	}
}
