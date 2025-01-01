package client

import (
	"time"

	"github.com/github/go-stats"
)

var _ = stats.Client(&multiStatsClient{})

// multiStatsClient is a stats.Client implementation which allows multiple stats.Client instances
// to be invoked under a single statter.  This allow us to emit stats to multiple backends without
// having to duplicate the stats calls in the client code.
//
// TODO(chriskirkland): consider upstreaming this to the go-stats library.
type multiStatsClient struct {
	clients []stats.Client
}

// Deprecated: use Run instead
func (c *multiStatsClient) Start() {
	for _, client := range c.clients {
		client.Start()
	}
}

func (c *multiStatsClient) Run() {
	for _, client := range c.clients {
		client.Run()
	}
}

func (c *multiStatsClient) Stop() {
	for _, client := range c.clients {
		client.Stop()
	}
}

func (c *multiStatsClient) Report(t stats.Type, key string, value float64, tags stats.Tags, rate float32) {
	for _, client := range c.clients {
		client.Report(t, key, value, tags, rate)
	}
}

func (c *multiStatsClient) Event(title, text string, tags stats.Tags) {
	for _, client := range c.clients {
		client.Event(title, text, tags)
	}
}

func (c *multiStatsClient) Gauge(key string, tags stats.Tags, value int64) {
	for _, client := range c.clients {
		client.Gauge(key, tags, value)
	}
}

func (c *multiStatsClient) Counter(key string, tags stats.Tags, value int64) {
	for _, client := range c.clients {
		client.Counter(key, tags, value)
	}
}

func (c *multiStatsClient) Histogram(key string, tags stats.Tags, value int64) {
	for _, client := range c.clients {
		client.Histogram(key, tags, value)
	}
}

func (c *multiStatsClient) Timing(key string, tags stats.Tags, value time.Duration) {
	for _, client := range c.clients {
		client.Timing(key, tags, value)
	}
}

func (c *multiStatsClient) Distribution(key string, tags stats.Tags, value float64) {
	for _, client := range c.clients {
		client.Distribution(key, tags, value)
	}
}

func (c *multiStatsClient) DistributionMs(key string, tags stats.Tags, value time.Duration) {
	for _, client := range c.clients {
		client.DistributionMs(key, tags, value)
	}
}

func (c *multiStatsClient) Set(key string, tags stats.Tags, value string) {
	for _, client := range c.clients {
		client.Set(key, tags, value)
	}
}

func (c *multiStatsClient) WithTags(tags stats.Tags) stats.Client {
	clients := make([]stats.Client, len(c.clients))
	for i, client := range c.clients {
		clients[i] = client.WithTags(tags)
	}
	return &multiStatsClient{clients: clients}
}

func (c *multiStatsClient) ClearTags() stats.Client {
	clients := make([]stats.Client, len(c.clients))
	for i, client := range c.clients {
		clients[i] = client.ClearTags()
	}
	return &multiStatsClient{clients: clients}
}

func (c *multiStatsClient) SetPrefix(prefix string) stats.Client {
	clients := make([]stats.Client, len(c.clients))
	for i, client := range c.clients {
		clients[i] = client.SetPrefix(prefix)
	}
	return &multiStatsClient{clients: clients}
}
