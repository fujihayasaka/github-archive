package observability

import (
	"maps"
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

// MetricTagsFn is a function that returns metric tags for a given request.
// It is called per-request in RoundTrip, allowing runtime flag evaluation.
type MetricTagsFn func(req *http.Request) stats.Tags

// TelemetryRoundTripper is a round tripper that captures telemetry data for outbound HTTP calls.
// It wraps an existing http.RoundTripper and adds metrics, tracing, and logging.
type TelemetryRoundTripper struct {
	rt           http.RoundTripper
	obsv         Exporters
	name         string // service name for metrics/traces
	metricTagsFn MetricTagsFn
}

// NewTelemetryRoundTripper creates a new telemetry round tripper that wraps the given round tripper.
// The name parameter is used to identify the service making the calls in metrics and traces.
func NewTelemetryRoundTripper(rt http.RoundTripper, obsv Exporters, name string, metricTagsFn MetricTagsFn) *TelemetryRoundTripper {
	if rt == nil {
		rt = http.DefaultTransport
	}

	// Wrap the round tripper with OpenTelemetry instrumentation to create spans and open telemetry metrics.
	// This will create another span, inside ours but to reduce changes and give us time to test this more
	// carefully we are keeping both for now.
	rt = otelhttp.NewTransport(rt)

	return &TelemetryRoundTripper{
		rt:           rt,
		obsv:         obsv,
		name:         name,
		metricTagsFn: metricTagsFn,
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

	// Evaluate metric tags once per request (flag check + tag construction).
	var extraTags stats.Tags
	if t.metricTagsFn != nil {
		if fnTags := t.metricTagsFn(req); fnTags != nil {
			if len(fnTags) > 0 {
				extraTags = maps.Clone(fnTags)
			}
			if req.Header.Get("Request-HMAC") != "" {
				if extraTags == nil {
					extraTags = stats.Tags{}
				}
				extraTags["auth_type"] = "hmac"
			}
		}
	}
	if methodName != "" {
		if extraTags == nil {
			extraTags = stats.Tags{}
		}
		extraTags["rpc_method"] = methodName
	}

	// Common tags for metrics
	tags := stats.Tags{
		"method":      req.Method,
		"host":        req.URL.Host,
		"client_name": t.name,
	}
	if len(extraTags) > 0 {
		maps.Copy(tags, extraTags)
	}

	kvps := []kvp.Field{
		kvp.String("http.method", req.Method),
		kvp.String("http.target", req.URL.Path),
		kvp.String("http.host", req.URL.Host),
		kvp.String("client.name", t.name),
		kvp.Duration("duration", duration),
	}
	if methodName != "" {
		kvps = append(kvps, kvp.String("rpc.method", methodName))
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

	// Emit GitHub API metrics. go-stats applies the service namespace.
	apiTags := stats.Tags{
		"method":      req.Method,
		"client_name": t.name,
	}
	if len(extraTags) > 0 {
		maps.Copy(apiTags, extraTags)
	}
	if resp != nil {
		apiTags["status_code"] = strconv.Itoa(resp.StatusCode)
		apiTags["status_class"] = strconv.Itoa(resp.StatusCode/100) + "xx"
	} else {
		apiTags["status_code"] = "0"
		apiTags["status_class"] = "error"
	}

	t.obsv.Statter.WithTags(maps.Clone(apiTags)).Counter("github.api.request", stats.Tags{}, 1)

	if resp != nil && resp.StatusCode >= 400 {
		t.obsv.Statter.WithTags(maps.Clone(apiTags)).Counter("github.api.error", stats.Tags{}, 1)
	}
	if err != nil {
		errorTags := maps.Clone(apiTags)
		errorTags["status_code"] = "0"
		errorTags["status_class"] = "error"
		t.obsv.Statter.WithTags(errorTags).Counter("github.api.error", stats.Tags{}, 1)
	}

	// Emit rate limit remaining as a gauge when present
	if resp != nil {
		if remaining := resp.Header.Get("X-Ratelimit-Remaining"); remaining != "" {
			val, parseErr := strconv.ParseFloat(remaining, 64)
			if parseErr == nil {
				rlTags := stats.Tags{
					"client_name": t.name,
					"resource":    resp.Header.Get("X-Ratelimit-Resource"),
				}
				if len(extraTags) > 0 {
					maps.Copy(rlTags, extraTags)
				}
				t.obsv.Statter.WithTags(rlTags).Distribution("github.api.rate_limit_remaining", stats.Tags{}, val)
			}
		}
	}

	return resp, err
}
