package trace

import (
	"context"
	"io"

	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/sdk/resource"
	otelSdk "go.opentelemetry.io/otel/sdk/trace"
)

type exporterType int

// configure some constants to select the correct exporter
const (
	ExporterOtlpHTTP exporterType = iota // production, send the trace data to an exporter
	ExporterStdout                       // send trace data to stdout, NOTE: don't use this in production
	ExporterDiscard                      // discard all trace output uses stdout TODO: does in memory exporter not exist? https://github.com/open-telemetry/opentelemetry-go#export
	ExporterUnknown                      // same as ExporterNever
)

// Config is used to configure the tracing system.
//
// The common usage will be that this struct is filled with values from environment variables.
type Config struct {
	Environment string `config:",env=GITHUB_TELEMETRY_ENVIRONMENT"`

	// Deprecated: this field is no longer in use
	IgnoredKeys string

	// We load endpoint to determine if we should automatically enable the exporter or not
	// When env vars are set we'll configure exporter to be exporter = withExporterBatched, otherwise we'll use withExporterNever
	// Use trace.WithExporter to override this behavior
	// For more info read:
	// https://opentelemetry.io/docs/concepts/sdk-configuration/otlp-exporter-configuration/#otel_exporter_otlp_traces_endpoint
	// https://opentelemetry.io/docs/concepts/sdk-configuration/otlp-exporter-configuration/#otel_exporter_otlp_endpoint
	OtelExpOtlpTracesEndpoint string `config:",env=OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"`
	OtelExpOtlpEndpoint       string `config:",env=OTEL_EXPORTER_OTLP_ENDPOINT"`

	// There are other settings to look at as well if apps need to override
	// https://opentelemetry.io/docs/concepts/sdk-configuration/otlp-exporter-configuration/#otel_exporter_otlp_timeout

	environment       string
	ctx               context.Context
	exporter          exporterType
	exporterWriter    io.Writer
	resource          *resource.Resource             // used for getting the tracer resource default values
	providerOptions   []otelSdk.TracerProviderOption // used to instrument tracer provider
	serviceName       *string                        // optional service name to use for the tracer otherwise we use SERVICE_NAME
	serviceVersion    *string                        // optional service version to use for the tracer otherwise we use SERVICE_VERSION
	instanceID        *string                        // configures the resource instanceID as extra attribute
	httpClientOptions []otlptracehttp.Option         // used to configure the HTTP client for the OTLP exporter
}
