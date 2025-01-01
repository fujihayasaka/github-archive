// Package statter implements a stats API that uses github/go-stats
package statter

import (
	"context"
	"expvar"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/github/go-stats"
	"github.com/github/go-stats/ps"
	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/pkg/launchconfig"
)

// Tags is an alias of map[string]string, a type for tags associated with a statistic.
type Tags stats.Tags

// Merge wraps stats.Tags.Merge
func (t Tags) Merge(tags Tags) Tags {
	return Tags(stats.Tags(t).Merge(stats.Tags(tags)))
}

// Statter represents a statsd-like reporter.
type Statter interface {
	// Prefix returns the prefix for all stat keys.
	Prefix() string

	// Client returns the stats client.
	Client() stats.Client

	// Start starts the stats client as well as the periodic process stats reporter.
	// This function must be called before attempting to report any metrics, or the
	// client will panic.
	Start()

	// Stop cleanly shuts down the stats client, flushing all buffered metrics.
	// Reporting metrics after the client has stopped will cause a panic.
	Stop()

	// Counter increments a statsd-like counter with optional tags.
	Counter(ctx context.Context, key string, tags Tags, value int64)

	// SampledCounter increments a statsd-like counter with optional tags.
	SampledCounter(ctx context.Context, key string, tags Tags, value int64, rate float32)

	// Gauge increments a statsd-like gauge ("set" of the value) with optional tags. Note: be careful using this, Histogram or Counter may be more appropriate
	Gauge(ctx context.Context, key string, tags Tags, value int64)

	// Histogram records a value in a distribution of values observed during the interval
	Histogram(ctx context.Context, key string, tags Tags, value int64)

	// Distribution records a value in a distribution of values observed during the interval, it is equivalent to a histogram
	// except every instance is reported instead of averages, making for more accurate percentiles
	Distribution(ctx context.Context, key string, tags Tags, value float64)

	// Timing logs a timing as a distribution of values observed during the interval, in milliseconds.
	Timing(ctx context.Context, key string, tags Tags, timing time.Duration)

	// SampledGauge increments a statsd-like gauge ("set" of the value) with optional tags.
	SampledGauge(ctx context.Context, key string, tags Tags, value int64, rate float32)

	// LegacyTimer returns a new LegacyTimer that records the current time. Calling End() on the
	// timer will send the time, in milliseconds, to the stats backend.
	//
	// Deprecated: Prefer statter.Timing, which uses a distribution.
	LegacyTimer() *LegacyTimer

	// LegacyTiming records a statsd-like timer with optional tags.
	LegacyTiming(ctx context.Context, key string, tags Tags, value time.Duration)

	// LegacySampledTiming records a statsd-like timer with optional tags.
	LegacySampledTiming(ctx context.Context, key string, tags Tags, value time.Duration, rate float32)

	// Event sends a DataDog event.
	Event(ctx context.Context, title, text string, tags Tags)

	// Periodically calls the function every Period seconds, passing itself in.
	// This can be used to periodically send stats without requiring the caller to spin
	// up their own goroutines.
	Periodically(f func(Statter))
}

type statter struct {
	prefix        string
	period        time.Duration // Period at which periodic stats are sent
	client        stats.Client
	periodics     []func(Statter)
	periodicsLock sync.RWMutex
}

// Config is the statter config
type Config struct {
	Addr   string
	Log    bool
	Prefix string
	Period time.Duration
	Tags   Tags
}

var defaultStatter struct {
	once sync.Once
	s    *statter
}

// DefaultStatter returns a statter instance initialized from the global config and Started.
// LoadConfig should be called before calling this function.
func DefaultStatter() *statter {
	defaultStatter.once.Do(func() {
		var s *statter
		if launchconfig.UseNullStatter() || launchconfig.StatsAddr() == "" {
			s = NullStatter()
		} else {
			launchProcess := "unknown"
			if executablePath, err := os.Executable(); err == nil {
				launchProcess = filepath.Base(executablePath)
			}

			s = New(&Config{
				Addr:   launchconfig.StatsAddr(),
				Prefix: launchconfig.StatsPrefix(),
				Period: launchconfig.StatsPeriod(),
				Tags: Tags{
					"launch_service": launchProcess,
					"launch_env":     launchconfig.EnvironmentTag(),
				},
			})
		}
		s.Start()
		defaultStatter.s = s
	})

	return defaultStatter.s
}

// New creates a new Statter
func New(cfg *Config) *statter {
	sink := io.Discard
	if cfg.Log {
		sink = os.Stderr
	} else if len(cfg.Addr) > 0 {
		sink = stats.UDPSink(cfg.Addr)
	}

	var client stats.Client
	client = stats.NewClient(sink, time.Second, cfg.Prefix, stats.WithChannelExceededReporting())

	if cfg.Tags != nil {
		client = client.WithTags(stats.Tags(cfg.Tags))
	}
	return &statter{
		prefix: cfg.Prefix,
		period: cfg.Period,
		client: client,
	}
}

// NullStatter creates a statter that discards all metrics.
func NullStatter() *statter {
	return &statter{
		client: stats.NullStatter,
	}
}

// Start starts the stats client as well as the periodic process stats reporter.
// This function must be called before attempting to report any metrics, or the
// client will panic.
func (s *statter) Start() {
	s.client.Run()

	if s.period > 0 {
		ps.Report(s.client, s.period)
		s.startPeriodics()
	}
}

// Stop cleanly shuts down the stats client, flushing all buffered metrics.
// Reporting metrics after the client has stopped will cause a panic.
func (s *statter) Stop() {
	s.client.Stop()
}

// Prefix returns the prefix for all stat keys.
func (s *statter) Prefix() string {
	return s.prefix
}

// Client returns the stats client.
func (s *statter) Client() stats.Client {
	return s.client
}

// Counter increments a statsd-like counter with optional tags.
func (s *statter) Counter(ctx context.Context, key string, tags Tags, value int64) {
	s.SampledCounter(ctx, key, tags, value, 1.0)
}

// SampledCounter increments a statsd-like counter with optional tags.
func (s *statter) SampledCounter(ctx context.Context, key string, tags Tags, value int64, rate float32) {
	s.client.Report(stats.Counter, key, float64(value), convertTags(ctx, tags), rate)
}

// Gauge increments a statsd-like gauge ("set" of the value) with optional tags. Note: be careful using this, Histogram or Counter may be more appropriate
func (s *statter) Gauge(ctx context.Context, key string, tags Tags, value int64) {
	s.SampledGauge(ctx, key, tags, value, 1.0)
}

// Histogram records a value in a distribution of values observed during the interval
func (s *statter) Histogram(ctx context.Context, key string, tags Tags, value int64) {
	s.client.Report(stats.Histogram, key, float64(value), convertTags(ctx, tags), 1.0)
}

// Distribution records a value in a distribution of values observed during the interval, it is equivalent to a histogram
// except every instance is reported instead of averages, making for more accurate percentiles
func (s *statter) Distribution(ctx context.Context, key string, tags Tags, value float64) {
	s.client.Report(stats.Distribution, key, value, convertTags(ctx, tags), 1.0)
}

// Log a timing as a distribution of values observed during the interval, in milliseconds.
func (s *statter) Timing(ctx context.Context, key string, tags Tags, timing time.Duration) {
	value := float64(timing) / float64(time.Millisecond)
	s.client.Report(stats.Distribution, key, value, convertTags(ctx, tags), 1.0)
}

// SampledGauge increments a statsd-like gauge ("set" of the value) with optional tags.
func (s *statter) SampledGauge(ctx context.Context, key string, tags Tags, value int64, rate float32) {
	s.client.Report(stats.Gauge, key, float64(value), convertTags(ctx, tags), rate)
}

// LegacyTiming records a statsd-like timer with optional tags.
func (s *statter) LegacyTiming(ctx context.Context, key string, tags Tags, value time.Duration) {
	s.LegacySampledTiming(ctx, key, tags, value, 1.0)
}

// LegacySampledTiming records a statsd-like timer with optional tags.
func (s *statter) LegacySampledTiming(ctx context.Context, key string, tags Tags, value time.Duration, rate float32) {
	s.client.Report(stats.Timing, key, float64(value)/float64(time.Millisecond), convertTags(ctx, tags), rate)
}

// Event sends a DataDog event.
func (s *statter) Event(ctx context.Context, title, text string, tags Tags) {
	s.client.Event(title, text, convertTags(ctx, tags))
}

// Periodically calls the function every Period seconds, passing itself in.
// This can be used to periodically send stats without requiring the caller to spin
// up their own goroutines.
func (s *statter) Periodically(f func(Statter)) {
	s.periodicsLock.Lock()
	s.periodics = append(s.periodics, f)
	s.periodicsLock.Unlock()
}

func (s *statter) startPeriodics() {
	go func() {
		for {
			s.periodicsLock.RLock()
			for i := 0; i < len(s.periodics); i++ {
				s.periodics[i](s)
			}
			s.periodicsLock.RUnlock()
			time.Sleep(s.period)
		}
	}()
}

// eventKeys is the set of circuit breaker events we would like sent to the
// metrics system.
var eventKeys = map[circuit.BreakerEvent]string{
	circuit.BreakerTripped: "tripped",
	circuit.BreakerReset:   "reset",
	circuit.BreakerReady:   "ready",
}

// MonitorCircuitBreaker starts up monitors for the circuit breaker. This
// monitors the number of failures and error rates as well as the breaker events
// defined in eventKeys.
func MonitorCircuitBreaker(ctx context.Context, s Statter, name string, breaker *circuit.Breaker) {
	failuresKey := fmt.Sprintf("circuit.%s.failures", name)
	successesKey := fmt.Sprintf("circuit.%s.successes", name)
	rateKey := fmt.Sprintf("circuit.%s.error_rate", name)

	s.Periodically(func(c Statter) {
		c.Gauge(ctx, failuresKey, nil, breaker.Failures())
		c.Gauge(ctx, successesKey, nil, breaker.Successes())
		c.Gauge(ctx, rateKey, nil, int64(breaker.ErrorRate()*100))
	})

	expvar.Publish(failuresKey, expvar.Func(func() any {
		return breaker.Failures()
	}))

	expvar.Publish(rateKey, expvar.Func(func() any {
		return breaker.ErrorRate()
	}))

	bc := make(chan circuit.ListenerEvent, 1)
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case e := <-bc:
				if key, ok := eventKeys[e.Event]; ok {
					s.Event(
						ctx,
						"Circuit Breaker Event",
						key,
						Tags{"app": s.Prefix(), "type": "circuitbreaker", "state": key, "name": name})
				}
			}
		}
	}()

	breaker.AddListener(bc)
}

func convertTags(ctx context.Context, tags Tags) stats.Tags {
	stashTags := ctxstash.From(ctx).Tags()
	nt := contextTags(ctx)
	nt = nt.Merge(Tags(stashTags))
	nt = nt.Merge(tags)
	return stats.Tags(nt)
}

// LegacyTimer returns a new LegacyTimer that records the current time. Calling End() on the
// timer will send the time, in milliseconds, to the stats backend.
//
// Deprecated: Prefer statter.Timing, which uses a distribution.
func (s *statter) LegacyTimer() *LegacyTimer {
	return NewLegacyTimer(s)
}

// LegacyTimer provides an encapsulation around a start time and a method for sending
// the elapsed time to the stats backend.
//
// Deprecated: Prefer statter.Timing, which uses a distribution.
type LegacyTimer struct {
	start  time.Time
	client *statter
}

// NewLegacyTimer creates a new timer using the Statter
//
// Deprecated: Prefer statter.Timing, which uses a distribution.
func NewLegacyTimer(s *statter) *LegacyTimer {
	return &LegacyTimer{
		start:  time.Now(),
		client: s,
	}
}

// Start returns the time the Timer was created.
//
// Deprecated: Prefer statter.Timing, which uses a distribution.
func (t *LegacyTimer) Start() time.Time {
	return t.start
}

// End sends the timer's elapsed time to the stats backend
//
// Deprecated: Prefer statter.Timing, which uses a distribution.
func (t *LegacyTimer) End(ctx context.Context, key string) {
	t.Log(ctx, time.Now(), key, nil)
}

// Log sends the elapsed time between the timer's start and the given time
//
// Deprecated: Prefer statter.Timing, which uses a distribution.
func (t *LegacyTimer) Log(ctx context.Context, end time.Time, key string, tags Tags) {
	t.client.LegacyTiming(ctx, key, tags, end.Sub(t.start))
}

func contextTags(ctx context.Context) Tags {
	if rmd, ok := ctx.Value(reqmeta.RMDContextKey).(*reqmeta.RequestMetadata); ok {
		return Tags(rmd.StatTags())
	}
	return nil
}
