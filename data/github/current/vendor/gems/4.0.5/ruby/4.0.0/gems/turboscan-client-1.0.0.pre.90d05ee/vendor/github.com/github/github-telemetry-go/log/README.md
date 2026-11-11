# Logging

This module's logging API resembles that of [github/go-log](https://github.com/github/go-log) and [github/go-kvp](https://github.com/github/go-kvp), which should make migrating from those libraries straightforward.

This module re-exports helper functions from the [github-semantic-conventions repo](https://github.com/github/github-semantic-conventions/tree/main/go).

## Basic Usage

Creating a logger is done like this:

```go
import (
 "github.com/github/github-telemetry-go/log"
 "github.com/github/github-telemetry-go/telemetry"
)

func main() {
 telem, err := telemetry.NewFromEnv()
 if err != nil {
	log.LogfmtError("Failed configuring telemetry", err)
  os.Exit(1)
 }

 defer func() {
  if err := telem.Shutdown(ctx); err != nil {
	 log.LogfmtError("Failed to shutdown telemetry", err)
   os.Exit(1)
  }
 }()

 logger := telem.Logger.WithFields(
   kvp.String("host.arch", "amd64"),
   kvp.String("cloud.platform", "aws_ec2"),
 )
 logger.Info("service has started")
}
```

### Global Logger

If you would like to have global access to the logger (in your current package), assign it to a global variable:

```go
var logger log.Logger

func main() {
 telem, err := telemetry.NewFromEnv()
 if err != nil {
	log.LogfmtError("Failed configuring telemetry", err)
  os.Exit(1)
 }
 logger = telem.Logger.Named("your-service-logger") // you can use any of the logger creation methods
 // ...
}
```

### Correlating Logs with Traces using WithSpanContext

When working with distributed tracing, you can correlate log entries with traces by using `WithSpanContext`. This method extracts the OpenTelemetry span context (span ID, trace ID, and trace flags) from the context and automatically appends these fields to all log entries:

```go
import (
 "context"
 "github.com/github/github-telemetry-go/log"
 "github.com/github/github-telemetry-go/telemetry"
)

func handleRequest(ctx context.Context, logger log.Logger) {
  // Assuming ctx contains an active OpenTelemetry span
  // WithSpanContext will extract trace.span_id, trace.trace_id, and trace.trace_flags
  logger.WithSpanContext(ctx).Info("Processing request", kvp.String("user_id", "12345"))
  
  // The log entry will now include:
  // - SpanId
  // - TraceId  
  // - TraceFlags
  
  // This allows you to correlate logs with distributed traces in your observability platform
}
```

**Key Points:**
- Use `WithSpanContext` to automatically add trace context to logs
- Only works when there's an active span in the context
- If no span is present, the logger is returned unchanged (no error)
- The trace fields allow you to find all logs associated with a specific trace

### Adapter for Http server error handler

If you're using `http.server` by default it will log the errors using logger from the standard library. This module provides StdLogAdapter to output these logs in a standard structured format:

```go
import (
 "github.com/github/github-telemetry-go/log"
 "github.com/github/github-telemetry-go/telemetry"
)

func main() {
  telem, err := telemetry.NewFromEnv()
    if err != nil {
		log.LogfmtError("Failed configuring telemetry", err)
    os.Exit(1)
  }

  serverLogger := log.StdLogAdapter(telem.Logger.Named("http.server").Error)

  server := &http.Server{
    Addr:     ":8080",
    ErrorLog: serverLogger,
    // ...
  }
}
```
