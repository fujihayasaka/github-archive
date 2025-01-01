package trace

import (
	"context"
	"fmt"
	"io"
	"runtime"

	"github.com/rs/xid"

	"go.opentelemetry.io/otel/attribute"

	version "github.com/github/github-telemetry-go"
	"github.com/github/github-telemetry-go/propagators"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	stdout "go.opentelemetry.io/otel/exporters/stdout/stdouttrace"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	otelSdk "go.opentelemetry.io/otel/sdk/trace"
	otelTrace "go.opentelemetry.io/otel/trace"
)

func ptr[T any](v T) *T { return &v }

// processConfig constructs a tracing config
//
// The priority of settings are:
//  1. Specified in code for testing (via the opts argument)
//  2. Otherwise whatever is specified in the packed OTEL_RESOURCE_ATTRIBUTES env var. For example, the
//     deployment.environment field inside OTEL_RESOURCE_ATTRIBUTES variable is used to specify the
//     environment (development or production).
//  3. Otherwise library-specific environment variables (which have been parsed into the config argument)
//  4. Otherwise user-provided options passed via userConfig and opts
//  5. Otherwise fall back to the hard-coded defaults
func processConfig(userConfig Config, opts ...TracerOption) (*Tracer, error) {
	// The sane way to deal with multi-level configs is to process them in reverse, overwriting the
	// hard-coded defaults with the higher priority choices.

	// ------------------------------------------------------------------------
	// Hard-coded defaults
	cfg := Config{
		serviceVersion: ptr("unknown_version"),
		environment:    "development",
	}

	// ------------------------------------------------------------------------
	// Set user provided options on the provided user config
	for _, opt := range opts {
		opt(&userConfig)
	}

	// ------------------------------------------------------------------------
	// Library-specific environment variables override hard-coded defaults

	// GITHUB_TELEMETRY_ENVIRONMENT
	// Can be an arbitrary string. Can be overridden by values provided in OTEL_RESOURCE_ATTRIBUTES
	// (which could be injected by kubernetes in moda).
	if userConfig.Environment != "" {
		cfg.environment = userConfig.Environment
	}

	// determine the defaults for the kind of exporter we'll setup
	cfg.exporter = ExporterDiscard
	if userConfig.OtelExpOtlpTracesEndpoint != "" || userConfig.OtelExpOtlpEndpoint != "" {
		cfg.exporter = ExporterOtlpHTTP
	}

	// ------------------------------------------------------------------------
	// OTEL_RESOURCE_ATTRIBUTES override library-specific environment variables
	for _, kv := range resource.Environment().Attributes() {
		switch {
		case kv.Key == attribute.Key("deployment.environment"):
			// deployment.environment subkey overrides value from GITHUB_TELEMETRY_ENVIRONMENT
			if val := kv.Value.AsString(); val != "" {
				cfg.environment = val
			}
		case kv.Key == attribute.Key("service.name"):
			if val := kv.Value.AsString(); val != "" {
				cfg.serviceName = &val
			}
		case kv.Key == attribute.Key("service.version"):
			if val := kv.Value.AsString(); val != "" {
				cfg.serviceVersion = &val
			}
		}
	}

	// ------------------------------------------------------------------------
	// Passed-in options override everything else (done by tests)
	for _, opt := range opts {
		opt(&cfg)
	}

	// resource defaults
	resdef := resource.Default()

	// Configure remaining defaults when not set
	if cfg.instanceID == nil {
		xID := xid.New().String()
		cfg.instanceID = &xID
	}

	// Map resources, we start with the default resources and add on config specific resources
	cfg.resource = mapResources(resdef, &cfg)

	// tracer instrumentation
	ctx := context.Background()
	if cfg.ctx != nil {
		ctx = cfg.ctx
	}

	client := otlptracehttp.NewClient(cfg.httpClientOptions...)

	// Determine which kind of exporter we're going to setup
	var exporterOpt otelSdk.TracerProviderOption
	var exporter otelSdk.SpanExporter
	var err error

	switch cfg.exporter {
	case ExporterOtlpHTTP:
		exporter, err = otlptrace.New(ctx, client)
		if err != nil {
			return nil, fmt.Errorf("failed to initialize normal exporter %w", err)
		}
		exporterOpt = otelSdk.WithBatcher(exporter)
	case ExporterStdout:
		var stdopts []stdout.Option
		stdopts = make([]stdout.Option, 0)
		stdopts = append(stdopts, stdout.WithPrettyPrint())
		if cfg.exporterWriter != nil {
			stdopts = append(stdopts, stdout.WithWriter(cfg.exporterWriter))
		}
		exporter, err := stdout.New(stdopts...)
		if err != nil {
			return nil, fmt.Errorf("failed to initialize stdout exporter %w", err)
		}
		exporterOpt = otelSdk.WithSyncer(exporter)
	case ExporterDiscard:
		exporter, err := stdout.New(stdout.WithWriter(io.Discard))
		if err != nil {
			return nil, fmt.Errorf("failed to initialize stdout exporter %w", err)
		}
		exporterOpt = otelSdk.WithBatcher(exporter)
	default:
		return nil, fmt.Errorf("unknown exporter type %v", cfg.exporter)
	}

	cfg.providerOptions = append(cfg.providerOptions, exporterOpt, otelSdk.WithResource(cfg.resource))

	tp := otelSdk.NewTracerProvider(cfg.providerOptions...)
	otel.SetTracerProvider(tp)

	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.Baggage{},
		propagation.TraceContext{},
		propagators.RequestIDPropagator{},
	))

	traceropts := []otelTrace.TracerOption{
		otelTrace.WithInstrumentationVersion(*resourceAttributeValue(cfg.resource, attribute.Key("service.version"))),
	}

	tracer := tp.Tracer(*resourceAttributeValue(cfg.resource, attribute.Key("service.name")), traceropts...)

	return &Tracer{
		config:   &cfg,
		Tracer:   tracer,
		Provider: tp,
	}, nil
}

// resourceAttributeValue returns a value from resource attributes
func resourceAttributeValue(r *resource.Resource, key attribute.Key) *string {
	for _, kv := range r.Attributes() {
		if kv.Key == key {
			res := kv.Value.AsString()
			return &res
		}
	}
	return nil
}

// mapResources helps us create a resources object to use in the tracer config
func mapResources(r *resource.Resource, cfg *Config) *resource.Resource {
	attrs := make([]attribute.KeyValue, 0, r.Len())
	attrs = append(attrs, r.Attributes()...)

	// Add the hostname to the resource
	hostNameResource, _ := resource.New(context.Background(), resource.WithHost())
	attrs = append(attrs, hostNameResource.Attributes()...)

	if cfg.serviceName != nil {
		attrs = append(attrs, attribute.Key("service.name").String(*cfg.serviceName))
	}
	if cfg.serviceVersion != nil {
		attrs = append(attrs, attribute.Key("service.version").String(*cfg.serviceVersion))
	}
	attrs = append(attrs,
		attribute.Key("process.runtime.version").String(runtime.Version()),
		attribute.Key("deployment.environment").String(cfg.environment),
		attribute.Key("service.instance.id").String(*cfg.instanceID),
		attribute.Key("gh.sdk.name").String(version.GlobalSDKName),
		attribute.Key("gh.sdk.version").String(version.GlobalSDKVersion),
	)
	return resource.NewWithAttributes(r.SchemaURL(), attrs...)
}
