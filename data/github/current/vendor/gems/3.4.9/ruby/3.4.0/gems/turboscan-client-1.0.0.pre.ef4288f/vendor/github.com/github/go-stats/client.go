// Package stats provides a statsd-compatible client for metrics reporting
package stats

import (
	"io"
	"net"
	"time"
)

// Type defines the different metric types that this client can report.
type Type byte

// These constants are nicely-named versions of the characters that need to be used.
const (
	Counter      Type = 'c'
	Gauge        Type = 'g'
	Histogram    Type = 'h'
	Timing       Type = 'h'
	Event        Type = 'e'
	Distribution Type = 'd'
	Set          Type = 's'
)

// Tags is a dictionary of tags (key-value pairs). The values can be empty
// for tags that are "unary".
//
// A Tags must be converted into a tagBuffer type to be used when reporting
// metrics. This conversion is performed by the Tags.tagBuffer() method, and
// should ideally be cached for performance.
type Tags map[string]string

// Merge creates a merged set of Tags. Tags passed in will overwrite current tags.
// Note that if either `t` or `tags` have length zero, the respective non-empty object will be returned
// and a new object will _not_ be created in that case. If both `t` and `tags` have length zero, the empty
// `tags` object is returned and a new object will _not_ be created in that case.
// This is a conscious decision to avoid re-allocation as this function is frequently called in hot codepaths.
func (t Tags) Merge(tags Tags) Tags {
	if len(t) == 0 {
		return tags
	}
	if len(tags) == 0 {
		return t
	}
	merged := make(Tags)
	for k, v := range t {
		merged[k] = v
	}
	for k, v := range tags {
		merged[k] = v
	}
	return merged
}

// Client is a generic interface for a Statsd-compatible metrics client.  It is
// defined this way to allow swapping the implementation of the underlying
// client.
//
//nolint:interfacebloat // That's, like, just your opinion man.
type Client interface {
	// Deprecated: use Run instead
	Start()
	Run()
	Stop()

	Report(t Type, key string, value float64, tags Tags, rate float32)
	Event(title, text string, tags Tags)

	Gauge(key string, tags Tags, value int64)
	Counter(key string, tags Tags, value int64)
	Increment(key string, tags Tags)
	Histogram(key string, tags Tags, value int64)
	Timing(key string, tags Tags, value time.Duration)
	Distribution(key string, tags Tags, value float64)
	DistributionMs(key string, tags Tags, value time.Duration)
	Set(key string, tags Tags, value string)

	WithTags(tags Tags) Client
	ClearTags() Client
	SetPrefix(prefix string) Client
}

// defaultDataDogAddr is the default address of the DataDog agent running on localhost.
// See: https://github.com/github/thehub/blob/main/docs/engineering/development-and-ops/moda/feature-documentation/metrics.md
// TODO: find out and document what causes Datadog Agent to listen on this port.
const defaultDataDogAddr = "127.0.0.1:28125"

// NewDataDogSink returns a Sink that writes to the default DataDog agent running on
// localhost.
func NewDataDogSink() (io.WriteCloser, error) {
	return NewUDPSink(defaultDataDogAddr)
}

// DataDogSink returns a Sink that writes to the default DataDog agent running on
// localhost.
// Deprecated: use NewDataDogSink.
func DataDogSink() io.Writer {
	return UDPSink(defaultDataDogAddr)
}

// NewUDPSink returns a Sink that writes to the given Statsd server using the UDP
// protocol.
func NewUDPSink(addr string) (io.WriteCloser, error) {
	udp, err := net.ResolveUDPAddr("udp", addr)
	if err != nil {
		return nil, err
	}
	fd, err := net.DialUDP("udp", nil, udp)
	if err != nil {
		return nil, err
	}
	return fd, nil
}

// UDPSink returns a Sink that writes to the given Statsd server using the UDP
// protocol.
// Deprecated: use NewUDPSink.
func UDPSink(addr string) io.Writer {
	udp, err := net.ResolveUDPAddr("udp", addr)
	if err != nil {
		panic(err)
	}
	fd, err := net.DialUDP("udp", nil, udp)
	if err != nil {
		panic(err)
	}
	return fd
}

// Timer provides an encapsulation around a start time and a method for sending
// the elapsed time to the stats backend.
type Timer struct {
	start  time.Time
	client Client
}

// NewTimer creates a new timer using the given Client.
func NewTimer(c Client) *Timer {
	return &Timer{
		start:  time.Now(),
		client: c,
	}
}

// StartTime returns the time the Timer was created.
func (t *Timer) StartTime() time.Time {
	return t.start
}

// Time sends the timer's elapsed time so far to the stats backend as a timing metric.
func (t *Timer) Time(key string, tags Tags) time.Duration {
	d := time.Since(t.start)
	t.client.Timing(key, tags, d)
	return d
}

// TimeDistribution sends the timer's elapsed time so far to the stats backend as a distribution metric.
func (t *Timer) TimeDistribution(key string, tags Tags) time.Duration {
	d := time.Since(t.start)
	t.client.DistributionMs(key, tags, d)
	return d
}

// NullClient is the "empty" Statsd client. Since it fulfills the Client interface, it
// can be used to disable metrics reporting e.g. when running an application in
// CI.
type NullClient struct{}

// Start does nothing.
func (*NullClient) Start() {}

// Run does nothing.
func (*NullClient) Run() {}

// Stop does nothing.
func (*NullClient) Stop() {}

// Report does nothing.
func (*NullClient) Report(t Type, key string, value float64, tags Tags, rate float32) {}

// Gauge does nothing.
func (*NullClient) Gauge(key string, tags Tags, value int64) {}

// Counter does nothing.
func (*NullClient) Counter(key string, tags Tags, value int64) {}

// Increment does nothing.
func (*NullClient) Increment(key string, tags Tags) {}

// Histogram does nothing.
func (*NullClient) Histogram(key string, tags Tags, value int64) {}

// Timing does nothing.
func (*NullClient) Timing(key string, tags Tags, value time.Duration) {}

// Event does nothing.
func (*NullClient) Event(title, text string, tags Tags) {}

// Distribution does nothing.
func (*NullClient) Distribution(key string, tags Tags, value float64) {}

// DistributionMs does nothing.
func (*NullClient) DistributionMs(key string, tags Tags, value time.Duration) {}

// Set does nothing.
func (*NullClient) Set(key string, tags Tags, value string) {}

// SetPrefix does nothing.
func (n *NullClient) SetPrefix(prefix string) Client { return n }

// WithTags does nothing.
func (n *NullClient) WithTags(tags Tags) Client { return n }

// ClearTags does nothing.
func (n *NullClient) ClearTags() Client { return n }

// NewNullClient returns a new instance of the NullClient.
//
// Deprecated: reference NullStatter directly instead of creating new instances.
func NewNullClient() *NullClient {
	return &NullClient{}
}

// NullStatter can be used when you want a stats client that can be called but does nothing.
var NullStatter = &NullClient{}
