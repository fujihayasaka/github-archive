package config

import (
	"log"
	"time"

	"github.com/github/go-stats"
)

// ConsoleLoggingClient is a locally logging Statsd client, because it sucks to debug stat blocks in deploy only.
// It disables metrics reporting, but logs all stats logs out to console
type ConsoleLoggingClient struct{}

func (ConsoleLoggingClient) Start() {}
func (ConsoleLoggingClient) Run()   {}
func (ConsoleLoggingClient) Stop()  {}
func (ConsoleLoggingClient) Report(t stats.Type, key string, value float64, tags stats.Tags, rate float32) {
	log.Printf("REPORTSTATS type %v key %v value %v tags %v rate %v", t, key, value, tags, rate)
}
func (ConsoleLoggingClient) Gauge(key string, tags stats.Tags, value int64) {
	log.Printf("GAUGESTATS key %v value %v tags %v", key, tags, value)
}
func (ConsoleLoggingClient) Counter(key string, tags stats.Tags, value int64) {
	log.Printf("COUNTERSTATS key %v tags %v value %v", key, tags, value)
}
func (ConsoleLoggingClient) Histogram(key string, tags stats.Tags, value int64) {
	log.Printf("HISTOGRAMSTATS key %v tags %v value %v", key, tags, value)
}
func (ConsoleLoggingClient) Timing(key string, tags stats.Tags, value time.Duration) {
	log.Printf("TIMINGSTATS key %v tags %v value %v", key, tags, value)
}
func (ConsoleLoggingClient) Event(title, text string, tags stats.Tags) {
	log.Printf("EVENTSTATS title %v text %v tags %v", title, text, tags)
}
func (ConsoleLoggingClient) Distribution(key string, tags stats.Tags, value float64) {
	log.Printf("DISTRIBUTIONSTATS key %v tags %v value %v", key, tags, value)
}
func (ConsoleLoggingClient) DistributionMs(key string, tags stats.Tags, value time.Duration) {
	log.Printf("DISTRIBUTIONMSSTATS key %v tags %v value %v", key, tags, value)
}
func (ConsoleLoggingClient) Increment(key string, tags stats.Tags) {
	log.Printf("INCREMENTSTATS key %v tags %v", key, tags)
}
func (ConsoleLoggingClient) Set(key string, tags stats.Tags, value string) {}
func (n *ConsoleLoggingClient) WithTags(tags stats.Tags) stats.Client      { return n }

// ClearTags clears the tags on the client
func (n *ConsoleLoggingClient) ClearTags() stats.Client {
	return n
}

// SetPrefix sets the prefix on the client
func (n *ConsoleLoggingClient) SetPrefix(prefix string) stats.Client {
	return n
}

// NewConsoleLoggingClient returns a new instance of the ConsoleLoggingClient
func NewConsoleLoggingClient() *ConsoleLoggingClient {
	return &ConsoleLoggingClient{}
}

var ConsoleLoggingStatter = &ConsoleLoggingClient{}
