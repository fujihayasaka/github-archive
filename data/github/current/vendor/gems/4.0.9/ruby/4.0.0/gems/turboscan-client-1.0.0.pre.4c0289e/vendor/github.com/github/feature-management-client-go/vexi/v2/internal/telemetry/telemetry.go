// Package telemetry holds the constants and common telemetry functionality for vexi-go.
package telemetry

import (
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"go.opentelemetry.io/otel/trace/noop"
)

// StatsClientWithHistogramRemapped is a stats client that remaps the Histogram to Distribution. This is a workaround to avoid
// having other libraries use the Histogram method which leads to multiple client aggregated metrics which are less flexible and
// hard to manage in datadog. See https://github.com/github/feature-management/issues/3971 for more details.
type StatsClientWithHistogramRemapped struct {
	stats.Client
}

// NewStatsClientWithHistogramRemapped creates a new stats client that remaps the Histogram to Distribution.
func NewStatsClientWithHistogramRemapped(c stats.Client) *StatsClientWithHistogramRemapped {
	return &StatsClientWithHistogramRemapped{Client: c}
}

// Histogram internally calls the Distribution method.
func (c *StatsClientWithHistogramRemapped) Histogram(key string, tags stats.Tags, value int64) {
	c.Distribution(key, tags, float64(value))
}

// NullTracer is a no-op tracer.
var NullTracer = noop.NewTracerProvider().Tracer("noop")

// NullLogger is a no-op logger.
var NullLogger = log.NewNullLogger()
