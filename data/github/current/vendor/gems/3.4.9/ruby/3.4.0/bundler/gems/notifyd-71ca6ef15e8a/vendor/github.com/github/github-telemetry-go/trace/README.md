# Tracing

Package trace provides a pre-configured OpenTelemetry Tracer for use on GitHub
applications. It provides a consistent way to interact with OpenTelemetry
tracing and emit telemetry to our observability systems with a required set of
resource attributes and a sane default configuration.

The implementation aims to provide an interface to the OpenTelemetry provided
tracing packages. It returns these objects pre-configured for compliance with
GitHub's standards for telemetry data.

## Basics

The trace package exposes two methods. NewFromEnv and NewFromConfig.

NewFromEnv uses environment variables to configure the tracer and returns
an error and a pointer to a Tracer that contains an tracer, tracer provider.

NewFromConfig uses a provided configuration to configure the tracer and returns
an error and a pointer to a Tracer that contains a tracer, tracer provider.

## Config

The following struct can be passed to NewFromConfig to configure a tracer

	type Config struct {
		Environment string config:",env=GITHUB_TELEMETRY_ENVIRONMENT"

		// We load endpoint to determine if we should automatically enable the exporter or not
		// When env vars are set we'll configure exporter to be exporter = withExporterBatched, otherwise we'll use withExporterNever
		// Use trace.WithExporter to override this behavior
		// For more info read:
		// https://opentelemetry.io/docs/concepts/sdk-configuration/otlp-exporter-configuration/#otel_exporter_otlp_traces_endpoint
		// https://opentelemetry.io/docs/concepts/sdk-configuration/otlp-exporter-configuration/#otel_exporter_otlp_endpoint
		OtelExpOtlpTracesEndpoint string config:",env=OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"
		OtelExpOtlpEndpoint       string config:",env=OTEL_EXPORTER_OTLP_ENDPOINT"

		// private properties redacted
	}

## Types

Tracer is a struct containing a tracer and a tracer provider that exposes a Shutdown method.

tracer is an instance of the upstream "go.opentelemetry.io/otel/trace" Tracer
and is named by the configuration provided or the value of OTEL_SERVICE_NAME.

tracer provider is an instance of the upstream "go.opentelemetry.io/otel/sdk/trace"
TracerProvider.

## Usage

We recommend that you use an abstraction when adding the tracer package to your application. An abstraction like this can help confine tracing to a single location in your codebase. Using this abstraction, you could then `tracing.Instrument` from a single location, and then `tracing.Start` to record a span. If you don't want a global tracing package, you're free to pass the tracer provider to your various package constructors.

If you use the abstraction below you can use tracing throughout your project like this:

```go
package main

import (
    "time"

    "github.com/github/your-service/internal/tracing"
    "github.com/github/github-telemetry-go/kvp"
    "go.opentelemetry.io/otel/attribute"
  )

func main() {
  shutdown, err := tracing.Instrument(logger)
  if err != nil {
    logger.Fatal("failed to start tracing", kvp.String("exception.message", err.Error()))
  }
  defer shutdown()

  doWork()
}

func doWork() {
  _, sp := tracing.Start(context.Background(), "new-trace", oteltrace.WithAttributes(attribute.String("code.function", "doWork")))
  defer sp.End()
  time.Sleep(time.Second * 5)
}

```


### Example Internal Tracing Package

```go
// internal/tracing
package tracing

import (
  "context"
  "fmt"
  "time"

  "github.com/github/github-telemetry-go/kvp"
  "github.com/github/github-telemetry-go/log"
  "github.com/github/github-telemetry-go/trace"
  "go.opentelemetry.io/otel"
  oteltrace "go.opentelemetry.io/otel/trace"
)

// tracer ensures that if Instrument was not called, a noop tracer will be available
var tracer = oteltrace.NewNoopTracerProvider().Tracer("noop")

func Start(ctx context.Context, spanName string, opts ...oteltrace.SpanStartOption) (context.Context, oteltrace.Span) {
  return tracer.Start(ctx, spanName, opts...)
}

// Instrument creates a telemetry provider and sets the tracer variable to
// the named tracer
func Instrument(l log.Logger) (func(), error) {
  otel.SetErrorHandler(&errorHandler{l})

  tp, err := trace.NewFromEnv()
  if err != nil {
    return nil, fmt.Errorf("could not start telemetry provider: %w", err)
  }

  tracer = tp.Tracer

  return func() {
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
      defer cancel()
      if err := tp.Provider.Shutdown(ctx); err != nil {
        l.Error("error shutting down tracer", kvp.String("err", err.Error()))
      }
  }, nil
}

type errorHandler struct {
  l log.Logger
}

func (eh errorHandler) Handle(err error) {
  if err != nil {
    eh.l.Error("encountered a problem during tracing", kvp.String("err", err.Error()))
  }
}
```
