package observability

import (
	"net/http"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/requestctx"
)

// TelemetryRoundTripper is a round tripper that captures telemetry data for outbound HTTP calls.
// It wraps an existing http.RoundTripper and adds metrics, tracing, and logging.
type TelemetryRoundTripper struct {
	rt   http.RoundTripper
	obsv Exporters
	name string // service name for metrics/traces
}

// NewTelemetryRoundTripper creates a new telemetry round tripper that wraps the given round tripper.
// The name parameter is used to identify the service making the calls in metrics and traces.
func NewTelemetryRoundTripper(rt http.RoundTripper, obsv Exporters, name string) *TelemetryRoundTripper {
	if rt == nil {
		rt = http.DefaultTransport
	}
	return &TelemetryRoundTripper{
		rt:   rt,
		obsv: obsv,
		name: name,
	}
}

// RoundTrip implements the http.RoundTripper interface with telemetry instrumentation.
func (t *TelemetryRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	start := time.Now()
	ctx := req.Context()

	// Execute the request
	resp, err := t.rt.RoundTrip(req)
	statsT, _, logKvps := requestctx.ToTelemetry(ctx, req)
	duration := time.Since(start)

	// Common tags for metrics
	tags := stats.Tags{
		"method":      req.Method,
		"host":        req.URL.Host,
		"client_name": t.name,
	}

	kvps := []kvp.Field{
		kvp.String("http.method", req.Method),
		kvp.String("http.target", req.URL.Path),
		kvp.String("http.host", req.URL.Host),
		kvp.String("client.name", t.name),
		kvp.Duration("duration", duration),
	}

	// Handle response or error
	if err != nil {
		// Record error
		tags["status"] = "error"
		tags["status_code"] = "0"

		// Log the error
		t.obsv.Logger.WithContext(ctx).WithFields(logKvps...).WithFields(kvps...).WithError(err).Error("HTTP request failed")
	} else {
		// Record successful response
		statusCode := resp.StatusCode
		statusClass := strconv.Itoa(statusCode / 100)

		tags["status"] = "success"
		tags["status_code"] = strconv.Itoa(statusCode)
		tags["status_class"] = statusClass + "xx"

		// Log successful requests at debug level
		logger := t.obsv.Logger.WithContext(ctx).WithFields(logKvps...).WithFields(kvps...).WithFields(
			kvp.Int("http.status_code", statusCode),
		)

		if statusCode >= 400 {
			logger.Warn("HTTP request completed with error status")
		} else {
			logger.Debug("HTTP request completed successfully")
		}
	}

	t.obsv.Statter.WithTags(statsT).WithTags(tags).DistributionMs("http_request_duration", stats.Tags{}, duration)

	return resp, err
}
