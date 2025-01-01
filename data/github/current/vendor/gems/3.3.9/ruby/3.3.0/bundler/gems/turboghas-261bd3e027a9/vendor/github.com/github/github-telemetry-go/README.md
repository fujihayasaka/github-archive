# github-telemetry-go

Centralized, default configurations for OpenTelemetry with Golang at GitHub

- [Logging at GitHub](https://thehub.github.com/epd/engineering/dev-practicals/observability/logging/opentelemetry-logging/)
- [Distributed Tracing](https://thehub.github.com/epd/engineering/dev-practicals/observability/distributed-tracing/)
- [Log Package Documentation](./log/README.md)
- [Trace Package Documentation](./trace/README.md)

## Requirements

- GitHub goproxy setup - please refer to the [user guide](https://github.com/github/goproxy/blob/main/doc/user.md)
- The library requires a minimum version for go to be 1.19, however 1.20+ is recommended.
- Set the `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` and `OTEL_EXPORTER_OTLP_TRACES_HEADERS` variables in the application's Vault ([hub documentation](https://thehub.github.com/epd/engineering/dev-practicals/observability/distributed-tracing/instrumentation/#configure-endpoints-and-authentication))
- Ensure the `OTEL_SERVICE_NAME` and `OTEL_RESOURCE_ATTRIBUTES` variables are set in the application's startup environment ([hub documentation](https://thehub.github.com/epd/engineering/dev-practicals/observability/language-guides/#otel-requirements-for-all-sdks))

## Basic Usage

```go
package main

import (
  "context"
  "fmt"
  "os"

  "github.com/github/github-telemetry-go/log"
  "github.com/github/github-telemetry-go/telemetry"
  "github.com/github/github-telemetry-go/trace"
)

func main() {
  ctx := context.Background()

  telem, err := telemetry.NewFromEnv()
  if err != nil {
    fmt.Printf("Failed configuring telemetry: %v", err)
    os.Exit(1)
  }

  defer func() {
    if err := telem.Shutdown(ctx); err != nil {
      fmt.Printf("failed to shutdown telemetry: %v", err)
    }
  }()

  // logging
  logger := telem.Logger.Named("service-logger")
  logger.Info("service has started")

  // tracing
  tracer := telem.Tracer.Tracer
  _, sp := tracer.Start(ctx, "main-span")
  defer sp.End()

  return nil
}
```

## Configuration

All configuration items have sane defaults. Configuration is achieved via environment
variables:

- `GITHUB_TELEMETRY_ENVIRONMENT`
  - Default: `development`
  - Valid values: `production`, `development`
  - Description: Whether the current environment is production or development.
- `GITHUB_TELEMETRY_LOGS_CONSOLE_ENCODING`
  - Default: `logfmt`
  - Valid values: `logfmt`, `json`, `console`
  - Description: Whether the logs to stdout are emitted† in terminal-friendly `console`, human-readable `logfmt` format or in `json` format.
- `GITHUB_TELEMETRY_LOGS_INCLUDE_RESOURCE_ATTRIBUTES`
  - Default: `service.name,service.version,service.instance.id,deployment.environment`
  - Valid values: Any valid opentelemetry resource keys, separated by commas.
  - Description: A string containing a comma-separated list of which OpenTelemetry resource keys to include in every log entry if found in the environment. Setting this environment variable to a blank string will clear the defaults. Kubernetes / moda will inject resources into the environment of a running application via [a different environment variable](https://opentelemetry-python.readthedocs.io/en/latest/sdk/environment_variables.html#envvar-OTEL_RESOURCE_ATTRIBUTES). `github-telemetry-go` itself internally injects `service.instance.id` (in the default list) and `process.runtime.version` (not in the default list).
- `GITHUB_TELEMETRY_LOGS_LEVEL`
  - Default: `info`
  - Valid values: `debug`, `info`, `warn`, `error`, `fatal`
  - Description: The level of severity at (or above) which the log will be emitted†.
- `GITHUB_TELEMETRY_LOGS_PRECISION`
  - Default: `nanosecond`
  - Valid values: `nanosecond`, `millisecond`, `second`,
  - Description: Whether the precision of log timestamps should be down to the nanosecond, millisecond, or just to the second.
- `GITHUB_TELEMETRY_LOGS_TZ`
  - Default: `utc`
  - Valid values: `utc`, `local`
  - Description: Whether the timezone of log timestamps should be UTC or the machine's local time
- `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` or `OTEL_EXPORTER_OTLP_ENDPOINT`
  - See https://thehub.github.com/epd/engineering/dev-practicals/observability/distributed-tracing/instrumentation/#configure-endpoints-and-authentication
- `OTEL_EXPORTER_OTLP_TRACES_HEADERS`
  - See https://thehub.github.com/epd/engineering/dev-practicals/observability/distributed-tracing/instrumentation/#configure-endpoints-and-authentication

## Compat packages

This library includes two compatibility packages at `log/compat` and `kvp/compat` that implement the APIs of [go-log](https://github.com/github/go-log) and [go-kvp](https://github.com/github/go-log) respectively. Those libraries are now deprecated. The compatibility packages are intended as a stop-gap solution to get services using the telemetry logger, until their owners are able to replace the actual library imports and usage in the code, from go-log and go-kvp to github-telemetry-go.

**Do not use these packages directly!** The only recommended way to use `log/compat` and `kvp/compat` is in a `replace` directive in the go.mod file of a service that currently imports go-log and/or go-kvp. This directive will redirect the deprecated libraries to the compatibility packages inside this library. No other code changes will be needed (you do not need to update each import statement). For example:

```
(go.mod)

module github.com/github/octogopher

go 1.21.2

replace github.com/github/go-log => github.com/github/github-telemetry-go/log/compat v1.0.0

replace github.com/github/go-kvp => github.com/github/github-telemetry-go/kvp/compat v1.0.0

require (
...
```

## Development

- [Development Docs](/docs/DEVELOPMENT.md)
