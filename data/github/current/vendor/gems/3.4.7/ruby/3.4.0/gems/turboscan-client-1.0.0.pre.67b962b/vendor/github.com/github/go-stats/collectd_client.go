package stats

import (
	"time"
)

// collectdClient is a wrapper for a Client that omits tags.
type collectdClient struct {
	client Client
}

var emptyTags = Tags{}

// Start calls Client.Start
//
// Deprecated: use Run instead.
func (c *collectdClient) Start() {
	c.client.Start()
}

// Run calls Client.Run.
func (c *collectdClient) Run() {
	c.client.Run()
}

// Stop calls Client.Stop.
func (c *collectdClient) Stop() {
	c.client.Stop()
}

// Report calls Client.Report omitting tags.
func (c *collectdClient) Report(t Type, key string, value float64, _ Tags, rate float32) {
	c.client.Report(t, key, value, emptyTags, rate)
}

// Gauge calls Client.Gauge omitting tags.
func (c *collectdClient) Gauge(key string, _ Tags, value int64) {
	c.client.Gauge(key, emptyTags, value)
}

// Counter calls Client.Counter omitting tags.
func (c *collectdClient) Counter(key string, _ Tags, value int64) {
	c.client.Counter(key, emptyTags, value)
}

// Increment calls Client.Increment omitting tags.
func (c *collectdClient) Increment(key string, _ Tags) {
	c.client.Increment(key, emptyTags)
}

// Histogram calls Client.Histogram omitting tags.
func (c *collectdClient) Histogram(key string, _ Tags, value int64) {
	c.client.Histogram(key, emptyTags, value)
}

// Timing calls Client.Timing omitting tags.
func (c *collectdClient) Timing(key string, _ Tags, value time.Duration) {
	c.client.Timing(key, emptyTags, value)
}

// Event calls Client.Event omitting tags.
func (c *collectdClient) Event(title, text string, _ Tags) {
	c.client.Event(title, text, emptyTags)
}

// Distribution calls the underlying Client.Timing (using a timing instead of a distribution)
// without tags.
func (c *collectdClient) Distribution(key string, _ Tags, value float64) {
	// value is a float64 representing milliseconds
	duration := time.Duration(int64(value * float64(time.Millisecond)))
	c.DistributionMs(key, emptyTags, duration)
}

// DistributionMs calls the underlying Client.Timing (using a timing instead of a distribution)
// without tags tags.
func (c *collectdClient) DistributionMs(key string, _ Tags, value time.Duration) {
	c.client.Timing(key, emptyTags, value)
}

// Set calls Client.Set omitting tags.
func (c *collectdClient) Set(key string, _ Tags, value string) {
	c.client.Set(key, emptyTags, value)
}

// WithTags returns the Client omitting tags.
func (c *collectdClient) WithTags(_ Tags) Client {
	return c
}

// ClearTags returns the Client and does nothing.
func (c *collectdClient) ClearTags() Client {
	return c
}

// SetPrefix returns a new client that has been reset to a different prefix. It uses the same
// writer, therefore the same sink as the receiver client.
func (c *collectdClient) SetPrefix(prefix string) Client {
	return &collectdClient{
		client: c.client.SetPrefix(prefix),
	}
}

// NewCollectdClient returns a wrapper that strips out tags and turns
// distributions into timing metrics to comply with Collectd Statsd
// plugin limitations on GHES.
func NewCollectdClient(client Client) Client {
	return &collectdClient{
		client: client,
	}
}
