package observability

import (
	"net/http"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/twitchtv/twirp"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel/attribute"
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

	// Wrap the round tripper with OpenTelemetry instrumentation to create spans and open telemetry metrics.
	// This will create another span, inside ours but to reduce changes and give us time to test this more
	// carefully we are keeping both for now.
	rt = otelhttp.NewTransport(rt)

	return &TelemetryRoundTripper{
		rt:   rt,
		obsv: obsv,
		name: name,
	}
}

// RoundTrip implements the http.RoundTripper interface with telemetry instrumentation.
func (t *TelemetryRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	ctx := req.Context()
	ctx, span := t.obsv.Tracer.Start(ctx, req.Method)
	defer span.End()

	span.SetAttributes(attribute.String("client.name", t.name),
		attribute.String("http.request.method", req.Method),
		attribute.String("server.address", req.URL.Hostname()),
		attribute.String("server.port", req.URL.Port()))

	methodName, ok := twirp.MethodName(ctx)
	if ok {
		span.SetAttributes(attribute.String("rpc.method", methodName))
	}

	req = req.WithContext(ctx)

	start := time.Now()

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
		span.RecordError(err)
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
