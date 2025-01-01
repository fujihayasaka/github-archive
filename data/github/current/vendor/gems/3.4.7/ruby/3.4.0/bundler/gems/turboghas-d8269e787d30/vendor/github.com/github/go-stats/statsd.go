package stats

import (
	"fmt"
	"io"
	"os"
	"strings"
	"time"
)

/*
ddEnvTagsMapping is a mapping of each "DD_" prefixed environment variable
to a specific tag name. We use a slice to keep the order and simplify tests.
*/
var ddEnvTagsMapping = []struct{ envName, tagName string }{
	{"DD_ENV", "env"},         // The name of the env in which the service runs.
	{"DD_SERVICE", "service"}, // The name of the running service.
	{"DD_VERSION", "version"}, // The current version of the running service.
}

// channelExceededMetricName is the name of the metric that is sent when the internal
// buffer is full and metrics are dropped. This is only used if [WithBlockingReport] is
// *not* used.
//
// Note, the name "metric_dropped_on_receive" matches datadog-go https://github.com/DataDog/datadog-go/blob/20af2dbfabbbe6bd0347780cd57ed931f903f223/statsd/telemetry.go#L282
const channelExceededMetricName = "go-stats.metric_dropped_on_receive"

// totalMetricsMetricName is the name of the counter metric that is recorded when
// a metric is successfully enqueued to be sent to Dogstatsd over UDP.
//
// Note, the name "metrics" matches datadog-go https://github.com/DataDog/datadog-go/blob/20af2dbfabbbe6bd0347780cd57ed931f903f223/statsd/telemetry.go#L272
const totalMetricsMetricName = "go-stats.metrics"

// Statsd represents a stats client.
type Statsd struct {
	w          *writer
	tags       tagBuffer
	sampleRate float32

	// prefix will be appended before the name of all outgoing metrics. If the
	// prefix does not end with a period `.`, one will be appended automatically.
	prefix string
}

// Start starts this stats client and blocks the current thread
//
// Deprecated: use Run instead.
func (st *Statsd) Start() {
	st.w.start()
}

// Run starts running the stats client on a background thread and returns immediately
// as soon as the stats client is ready to receive metrics.
func (st *Statsd) Run() {
	go st.w.start()
	st.w.starting.Wait()
}

// Stop stops running the client and blocks until it has exited.
func (st *Statsd) Stop() {
	st.w.stop()
	st.w.running.Wait()
}

// Report queues a metric to be reported via the specified writer.
// sampleRate must be a valid float between 0.0 and 1.0 inclusive, or this will panic.
func (st *Statsd) Report(t Type, key string, value float64, tags Tags, sampleRate float32) {
	validateSampleRate(sampleRate)

	st.w.enqueue(
		metric{prefix: st.prefix, name: key, value: value, char: t, rate: sampleRate, tags: tags.serialize(), conftags: st.tags},
	)
}

// Event reports an event.
func (st *Statsd) Event(title, text string, tags Tags) {
	st.w.enqueue(
		metric{prefix: st.prefix, char: Event, rate: 1.0, name: title, text: text, tags: tags.serialize(), conftags: st.tags},
	)
}

func (st *Statsd) with(newTags tagBuffer) Client {
	tags := append(defaultTags(), st.tags...)
	tags = append(tags, newTags...)

	result := &Statsd{
		w:          st.w,
		tags:       tags,
		sampleRate: st.sampleRate,
		prefix:     st.prefix,
	}

	// Reinitialize writer callbacks. Otherwise the callbacks
	// will not reference the new tags.
	setWriterCallbacks(result)

	return result
}

// WithTags adds tags to a Statsd and returns a Client interface.
func (st *Statsd) WithTags(tags Tags) Client {
	return st.with(tags.serialize())
}

// ClearTags returns a new Client with all the tags removed.
func (st *Statsd) ClearTags() Client {
	return &Statsd{
		w:          st.w,
		tags:       defaultTags(),
		prefix:     st.prefix,
		sampleRate: st.sampleRate,
	}
}

// SetPrefix returns a new client that has been reset to a different prefix. It uses the same
// writer, therefore the same sink as the receiver client.
func (st *Statsd) SetPrefix(prefix string) Client {
	return &Statsd{
		w:          st.w,
		tags:       st.tags,
		prefix:     regularizePrefix(prefix),
		sampleRate: st.sampleRate,
	}
}

// Gauge reports an individual Gauge metric. See `Report`.
func (st *Statsd) Gauge(key string, tags Tags, value int64) {
	st.Report(Gauge, key, float64(value), tags, st.sampleRate)
}

// Counter reports an individual Counter metric. See `Report`.
func (st *Statsd) Counter(key string, tags Tags, value int64) {
	st.Report(Counter, key, float64(value), tags, st.sampleRate)
}

// Histogram reports an individual Histogram metric. See `Report`.
func (st *Statsd) Histogram(key string, tags Tags, value int64) {
	st.Report(Histogram, key, float64(value), tags, st.sampleRate)
}

// Timing reports an individual Timing metric in milliseconds. See `Report`.
func (st *Statsd) Timing(key string, tags Tags, value time.Duration) {
	st.Report(Timing, key, float64(value)/float64(time.Millisecond), tags, st.sampleRate)
}

// Distribution reports a distribution metric. This variation takes value as a float64.
func (st *Statsd) Distribution(key string, tags Tags, value float64) {
	st.Report(Distribution, key, value, tags, st.sampleRate)
}

// DistributionMs reports a distribution metric. This variation takes value as a time.Duration.
func (st *Statsd) DistributionMs(key string, tags Tags, value time.Duration) {
	st.Report(Distribution, key, float64(value)/float64(time.Millisecond), tags, st.sampleRate)
}

// Set reports an individual Set metric. See `Report`.
func (st *Statsd) Set(key string, tags Tags, text string) {
	validateSampleRate(st.sampleRate)

	st.w.enqueue(
		metric{prefix: st.prefix, name: key, text: text, char: Set, rate: st.sampleRate, tags: tags.serialize(), conftags: st.tags},
	)
}

// WaitForStartup waits until the stats client has successfully started after a call to Start
//
// Deprecated: call stats.Run instead which will wait for the stats client to start up before
// returning.
func (st *Statsd) WaitForStartup() {
	st.w.starting.Wait()
}

// WaitForShutdown waits until the stats client has shut down after a call to Stop
//
// Deprecated: calling Stop now always waits for the client to stop before returning.
func (st *Statsd) WaitForShutdown() {
	// No-op
}

// ClientOption is a function that applies configuration to a Statsd during construction.
type ClientOption func(client *Statsd) error

// WithBlockingReport forces Report calls to block until space is available for the writer to
// consume the metric.
func WithBlockingReport(client *Statsd) error {
	client.w.block = true
	return nil
}

// WithSampleRate configures the rate at which samples will be recorded.
// 0.0 means no samples will be recorded, 1.0 means 100% of the samples will be recorded.
// however those samples may be later dropped if they overflow the metric writer's buffer.
// To avoid this, use WithBlockingReport.
func WithSampleRate(rate float32) func(client *Statsd) error {
	return func(client *Statsd) error {
		if rate < 0.0 || rate > 1.0 {
			return fmt.Errorf("the sample rate must be a valid float between 0.0 and 1.0, but was: %f", rate)
		}
		client.sampleRate = rate
		return nil
	}
}

// WithChannelSize configures the size of the channel used to buffer metrics before they are transmitted. The default
// size is 2048. Metrics will be dropped if the buffer is full and [WithBlockingReport] is *not* used.
func WithChannelSize(size int) func(client *Statsd) error {
	return func(client *Statsd) error {
		client.w.maxChannelSize = size
		return nil
	}
}

// WithChannelExceededReporting configures the client to report how many metrics have been dropped due to the internal
// buffer being full.
func WithChannelExceededReporting() func(client *Statsd) error {
	return func(client *Statsd) error {
		client.w.channelExceededReporting = true
		return nil
	}
}

// WithoutChannelExceededReporting configures the client NOT to report how many metrics have been dropped due to the internal
// buffer being full.
func WithoutChannelExceededReporting() func(client *Statsd) error {
	return func(client *Statsd) error {
		client.w.channelExceededReporting = false
		return nil
	}
}

// WithoutTotalMetricsReporting configures the client NOT to report how many metrics have been received.
func WithoutTotalMetricsReporting() func(client *Statsd) error {
	return func(client *Statsd) error {
		client.w.totalMetricsReporting = false
		return nil
	}
}

// setWriterCallbacks sets the writer callback functions for the client.
func setWriterCallbacks(client *Statsd) {
	// Factory for creating a new metric_dropped_on_receive metric. This is only used if
	// [WithBlockingReport] is *not* used.
	client.w.newChannelExceededMetric = func(count uint32) metric {
		return metric{
			prefix:   "", // Intentionally not writing the prefix for this metric
			name:     channelExceededMetricName,
			value:    float64(count),
			char:     Counter,
			rate:     1.0,
			conftags: client.tags,
		}
	}

	client.w.newMetricCountMetric = func(count uint32) metric {
		return metric{
			prefix:   "", // Intentionally not writing the prefix for this metric
			name:     totalMetricsMetricName,
			value:    float64(count),
			char:     Counter,
			rate:     1.0,
			conftags: client.tags,
		}
	}
}

// NewSampledClient creates a new statsd client that will only send a sample of recorded metrics
// at the specified sampleRate.
// sampleRate must be a valid float between 0.0 and 1.0 inclusive, or this will panic.
// If a ClientOption returns an error NewSampledClient will panic.
//
// Deprecated: use NewClient(sink, interval, prefix, WithSampleRate(sampleRate)).
func NewSampledClient(sink io.Writer, interval time.Duration, prefix string, sampleRate float32, opts ...ClientOption) *Statsd {
	// append client provided options _after_ WithSampleRate from parameters so the explicit
	// option applies last. This does mean you can call NewSampleClient(sink, interval, prefix, 0.0, WithSampleRate(1.0))
	// which is weird, but that's why this method is deprecated.
	opts = append([]ClientOption{WithSampleRate(sampleRate)}, opts...)
	return NewClient(sink, interval, prefix, opts...)
}

// NewClient creates a new statsd client with a default sample rate of 1.0 which will send every
// recorded metric.
// The sample rate can be overridden with the WithSampleRate ClientOption.
// If a ClientOption returns an error NewClient will panic.
func NewClient(sink io.Writer, interval time.Duration, prefix string, opts ...ClientOption) *Statsd {
	if interval == time.Duration(0) {
		interval = maxWriteDelay
	}

	client := &Statsd{
		w: &writer{
			Sink:                     sink,
			Interval:                 interval,
			totalMetricsReporting:    true,
			channelExceededReporting: true,
		},
		prefix: regularizePrefix(prefix),

		tags: defaultTags(),
	}

	// prepend WithSampleRate(1.0) option before the callers options. This allows the
	// caller to provide their own sample rate.
	opts = append([]ClientOption{WithSampleRate(1.0)}, opts...)
	for _, opt := range opts {
		if err := opt(client); err != nil {
			panic(fmt.Sprintf("client option failed: %v", err))
		}
	}

	setWriterCallbacks(client)
	client.w.starting.Add(1)

	return client
}

func defaultTags() tagBuffer {
	globalTags := parseGlobalTags()

	if globalTags == nil {
		return append(tagBuffer{}, parseTagEnvVars().serialize()...)
	}

	return append(parseGlobalTags().serialize(), parseTagEnvVars().serialize()...)
}

func parseGlobalTags() Tags {
	// Parse DD_TAGS environment variable and inject the values as global tags.
	ddTags := os.Getenv("DD_TAGS")
	if ddTags == "" {
		return nil
	}

	tags := Tags{}

	ddTagsSlice := strings.Split(ddTags, ",")
	for _, tag := range ddTagsSlice {
		tagElements := strings.Split(tag, ":")
		if len(tagElements) > 1 {
			tagName := tagElements[0]
			tagValue := tagElements[1]
			tags[tagName] = tagValue
		} else {
			tags[tag] = ""
		}
	}
	return tags
}

func parseTagEnvVars() Tags {
	tags := Tags{}
	// Inject values of DD_* environment variables as global tags.
	for _, mapping := range ddEnvTagsMapping {
		value := os.Getenv(mapping.envName)
		if value != "" {
			tags[mapping.tagName] = value
		}
	}
	return tags
}

func validateSampleRate(sampleRate float32) {
	if sampleRate < 0.0 || sampleRate > 1.0 {
		panic(fmt.Sprintf("The sample rate must be a valid float between 0.0 and 1.0, but was: %f", sampleRate))
	}
}
