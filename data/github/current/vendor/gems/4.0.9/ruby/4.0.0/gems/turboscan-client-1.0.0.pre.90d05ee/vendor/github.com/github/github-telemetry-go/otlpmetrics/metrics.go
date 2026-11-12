// Package otlpmetrics provides functionality to initialize OpenTelemetry OTLP metric exporters and a global
// [metric.MeterProvider] based on environment variables. See the README for more details.
package otlpmetrics

import (
	"context"
	"fmt"
	"net"
	"os"
	"strings"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/stdout/stdoutmetric"
	"go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/metric/metricdata"
	"go.opentelemetry.io/otel/sdk/resource"
	semconv "go.opentelemetry.io/otel/semconv/v1.37.0"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// DefaultMetricsPort is the default port for the OTLP metrics endpoint on the Kubernetes node.
const DefaultMetricsPort = "24317"

// NewFromEnv initializes an OTLP metric exporter and [metric.MeterProvider] from environment variables.
// Unless otherwise noted, all env vars are described and used as in https://opentelemetry.io/docs/specs/otel/configuration/sdk-environment-variables/
//   - OTEL_METRICS_EXPORTER: set to "none" to disable metrics export, "console" for stdout output, or "otlp" (default) to enable OTLP export.
//   - OTEL_EXPORTER_OTLP_METRICS_ENDPOINT: defaults to "http://<KUBE_NODE_IP>:24317" if not set, and KUBE_NODE_IP is non-empty.
//   - OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE: defaults to "delta" if not set.
//   - OTEL_METRIC_EXPORT_INTERVAL: defaults to 10000 (10 seconds) if not set.
//
// NOTE: HTTP proxy environment variables (HTTP_PROXY, HTTPS_PROXY, GRPC_PROXY) are ignored
// for OTLP connections since node-local endpoints should be accessed directly.
//
// NOTE: The MeterProvider is not shutdown automatically. The caller can use the [metric.MeterProvider.ForceFlush] and
// [metric.MeterProvider.Shutdown] functions to gracefully shutdown; if not done, some metrics may be lost during
// application exit.
func NewFromEnv() (*metric.MeterProvider, error) {
	// Only "none", "console", and "otlp" (or empty, defaulting to otlp) OTEL_METRICS_EXPORTERs are supported
	switch exporter := os.Getenv("OTEL_METRICS_EXPORTER"); exporter {
	case "none":
		return nil, nil
	case "console":
		return newStdoutMeterProvider()
	case "", "otlp":
		// Continue with OTLP exporter setup
	default:
		return nil, fmt.Errorf("unsupported OTEL_METRICS_EXPORTER value %q: only \"otlp\", \"console\", and \"none\" are supported", exporter)
	}

	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_METRICS_ENDPOINT")

	if endpoint == "" {
		// Default to the node-local OTLP endpoint using KUBE_NODE_IP
		kubeNodeIP := os.Getenv("KUBE_NODE_IP")
		if kubeNodeIP == "" {
			// Cannot construct default endpoint without KUBE_NODE_IP
			return nil, nil
		}
		//nolint:revive // http is intentional for node-local OTLP endpoint
		endpoint = "http://" + net.JoinHostPort(kubeNodeIP, DefaultMetricsPort)
		os.Setenv("OTEL_EXPORTER_OTLP_METRICS_ENDPOINT", endpoint)
	}

	// Enable metric observability feature flag in the go SDK.
	// The SDK feature flags metrics with the env var OTEL_GO_X_SELF_OBSERVABILITY (up to v1.38.0) or
	// OTEL_GO_X_OBSERVABILITY (v1.39.0+)
	os.Setenv("OTEL_GO_X_SELF_OBSERVABILITY", "true")
	os.Setenv("OTEL_GO_X_OBSERVABILITY", "true")

	if os.Getenv("OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE") == "" {
		// Set to "delta" temporality preference by default, to match Datadog's OTLP ingest requirements
		// The go SDK's default is "cumulative".
		os.Setenv("OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE", "delta")
	}

	if os.Getenv("OTEL_METRIC_EXPORT_INTERVAL") == "" {
		// Set to 10 second export interval by default, to match typical Datadog agent scrape interval
		// The go SDK's default is 60000ms (1 minute).
		os.Setenv("OTEL_METRIC_EXPORT_INTERVAL", "10000")
	}

	var exporterOpts []otlpmetricgrpc.Option

	// If the endpoint starts with "http://" then use insecure connection options
	if strings.HasPrefix(endpoint, "http://") {
		exporterOpts = append(exporterOpts,
			otlpmetricgrpc.WithDialOption(grpc.WithTransportCredentials(insecure.NewCredentials())),
			otlpmetricgrpc.WithInsecure(),
		)
	}

	// Disable proxy for node-local endpoints (derived from KUBE_NODE_IP) to prevent gRPC
	// from picking up http_proxy/https_proxy/grpc_proxy environment variables.
	// HTTP proxies don't support gRPC (HTTP/2) connections properly.
	if os.Getenv("KUBE_NODE_IP") != "" {
		exporterOpts = append(exporterOpts,
			otlpmetricgrpc.WithDialOption(grpc.WithNoProxy()),
		)
	}

	exporter, err := otlpmetricgrpc.New(context.Background(), exporterOpts...)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize OTLP grpc metric exporter: %w", err)
	}

	// Wrap the OTLP exporter to filter k8s.pod.name from resource attributes for non-otel.sdk.* metrics
	filteredExporter := newFilteredResourceExporter(exporter)

	mp := metric.NewMeterProvider(
		metric.WithReader(metric.NewPeriodicReader(filteredExporter)),
	)

	// Set the global meter provider
	otel.SetMeterProvider(mp)

	return mp, nil
}

// filteredResourceExporter wraps a metric exporter and filters k8s.pod.name
// from resource attributes for non-otel.sdk.* metrics before exporting.
// otel.sdk.* metrics (SDK self-observability metrics) retain k8s.pod.name
// for proper attribution in Datadog. This is necessary because the
// OpenTelemetry SDK doesn't provide a way to filter resource attributes
// per-metric (we want to keep k8s.pod.name for SDK metrics but remove it
// from application metrics to reduce cardinality).
type filteredResourceExporter struct {
	wrapped metric.Exporter
}

// Compile-time check that filteredResourceExporter implements [metric.Exporter].
var _ metric.Exporter = (*filteredResourceExporter)(nil)

func newFilteredResourceExporter(wrapped metric.Exporter) *filteredResourceExporter {
	return &filteredResourceExporter{wrapped: wrapped}
}

// newStdoutMeterProvider creates a MeterProvider that exports to stdout (for local dev and debugging).
func newStdoutMeterProvider() (*metric.MeterProvider, error) {
	stdoutOpts := []stdoutmetric.Option{
		stdoutmetric.WithPrettyPrint(),
	}

	// The stdout exporter does not use the usual SDK env var parsing, so we need to set these options manually.
	var temporality metricdata.Temporality
	switch os.Getenv("OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE") {
	case "cumulative":
		temporality = metricdata.CumulativeTemporality
	case "delta":
		temporality = metricdata.DeltaTemporality
	default:
		// Leave temporality as zero value, will be skipped below
	}
	if temporality != 0 {
		stdoutOpts = append(stdoutOpts, stdoutmetric.WithTemporalitySelector(
			func(descriptor metric.InstrumentKind) metricdata.Temporality {
				return temporality
			},
		))
	}

	stdoutExporter, err := stdoutmetric.New(stdoutOpts...)
	if err != nil {
		return nil, fmt.Errorf("failed to create stdout metric exporter: %w", err)
	}
	// Wrap stdout exporter with the same filter as OTLP for consistent behavior in tests
	filteredExporter := newFilteredResourceExporter(stdoutExporter)

	meterProvider := metric.NewMeterProvider(
		metric.WithReader(metric.NewPeriodicReader(filteredExporter)),
	)
	otel.SetMeterProvider(meterProvider)
	return meterProvider, nil
}

// otelSdkMetricPrefix is the prefix for OpenTelemetry SDK self-observability metrics.
const otelSdkMetricPrefix = "otel.sdk."

// Export filters k8s.pod.name from the resource for non-otel.sdk.* metrics.
// otel.sdk.* metrics retain the k8s.pod.name attribute for proper attribution.
// The filtering adds ~3μs overhead per export (benchmarked with typical resource attributes).
// This is negligible since exports happen once per OTEL_METRIC_EXPORT_INTERVAL (default: 10s)
// and are not in the hot path of metric recording. See metrics_bench_test.go for details.
func (e *filteredResourceExporter) Export(ctx context.Context, rm *metricdata.ResourceMetrics) error {
	var otelSdkScopes, otherScopes []metricdata.ScopeMetrics

	for _, sm := range rm.ScopeMetrics {
		if scopeHasOtelSdkMetric(sm) {
			otelSdkScopes = append(otelSdkScopes, sm)
		} else {
			otherScopes = append(otherScopes, sm)
		}
	}

	// Export otel.sdk.* scopes with original resource (including k8s.pod.name)
	if len(otelSdkScopes) > 0 {
		if err := e.wrapped.Export(ctx, &metricdata.ResourceMetrics{
			Resource:     rm.Resource,
			ScopeMetrics: otelSdkScopes,
		}); err != nil {
			return err
		}
	}

	// Export other scopes with filtered resource (k8s.pod.name removed)
	if len(otherScopes) > 0 {
		filter := attribute.NewDenyKeysFilter(semconv.K8SPodNameKey)
		filteredSet, _ := attribute.NewSetWithFiltered(rm.Resource.Attributes(), filter)
		filteredResource := resource.NewWithAttributes(rm.Resource.SchemaURL(), filteredSet.ToSlice()...)

		if err := e.wrapped.Export(ctx, &metricdata.ResourceMetrics{
			Resource:     filteredResource,
			ScopeMetrics: otherScopes,
		}); err != nil {
			return err
		}
	}

	return nil
}

// scopeHasOtelSdkMetric returns true if any metric in the scope has the otel.sdk.* prefix.
//
// In practice, otel.sdk.* metrics come from SDK-internal instrumentation scopes and should
// not be mixed with application metrics. However, we check every metric in the scope rather
// than relying on scope name alone. If otel.sdk.* and non-otel.sdk.* metrics are ever mixed
// in the same scope, the entire scope retains k8s.pod.name. This is the safe failure mode:
// over-tagging (keeping pod name when not strictly needed) rather than under-tagging
// (losing pod name for SDK metrics that need it for attribution).
func scopeHasOtelSdkMetric(sm metricdata.ScopeMetrics) bool {
	for _, m := range sm.Metrics {
		if strings.HasPrefix(m.Name, otelSdkMetricPrefix) {
			return true
		}
	}
	return false
}

// Temporality delegates to the wrapped exporter
func (e *filteredResourceExporter) Temporality(k metric.InstrumentKind) metricdata.Temporality {
	return e.wrapped.Temporality(k)
}

// Aggregation delegates to the wrapped exporter
func (e *filteredResourceExporter) Aggregation(k metric.InstrumentKind) metric.Aggregation {
	return e.wrapped.Aggregation(k)
}

// ForceFlush delegates to the wrapped exporter
func (e *filteredResourceExporter) ForceFlush(ctx context.Context) error {
	return e.wrapped.ForceFlush(ctx)
}

// Shutdown delegates to the wrapped exporter
func (e *filteredResourceExporter) Shutdown(ctx context.Context) error {
	return e.wrapped.Shutdown(ctx)
}
