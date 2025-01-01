# Telemetry

There are 4 types of telemetry in IMS:
- Logs (Splunk)
- Error reports (Sentry)
- Metrics (Datadog)
- Traces (Datadog)

Sentry reports and Datadog monitor alerts are sent to `#hosted-compute-ims-alerts` channel.

## Splunk (Logs)

We use [Splunk](https://thehub.github.com/epd/engineering/products-and-services/internal/splunk/) as logging platform. Logs are used for debugging application and issue investigation.

IMS has own Splunk index `hosted_compute_ims` for logs:
- [Lab](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3D%22hosted_compute_ims%22%20deployment.environment%3Dlab): `index="hosted_compute_ims" deployment.environment=lab`
- [Production](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3D%22hosted_compute_ims%22%20deployment.environment%3Dproduction): `index="hosted_compute_ims" deployment.environment=production`

> [!TIP]
> - Use `kube_container` to filter by application component (worker, api or replication job)
> - Use `SeverityText` to filter by log type (INFO, ERROR, DEBUG, etc)

## Sentry (Error reports)

We use [Sentry](https://thehub.github.com/epd/engineering/dev-practicals/observability/exception-tracking/) for exceptions tracking. It helps to manage application exceptions and group similar exceptions.

- [Lab](https://github.sentry.io/issues/?environment=production&project=4506904886116352&statsPeriod=24h)
- [Production](https://github.sentry.io/issues/?environment=production&project=4506904886116352&statsPeriod=24h)

Also, we use [integration](https://github.sentry.io/alerts/rules/hosted-compute-ims/15508615/details/) with Slack to publish all new error reports to `#hosted-compute-ims-alerts` Slack channel

## Datadog (Metrics and Traces)

We use [Datadog](https://thehub.github.com/epd/engineering/dev-practicals/observability/metrics/) for metrics collection, monitoring, tracing and dashboarding.

- IMS Availability dashboard: https://app.datadoghq.com/dashboard/vwb-6j5-4ry
- IMS Promotion dashboard: https://app.datadoghq.com/dashboard/qqu-6xx-9vu
- Monitors: https://app.datadoghq.com/monitors/manage?q=service%3A%22hosted-compute-ims%22&order=desc
- Traces: https://app.datadoghq.com/apm/services/hosted-compute-ims/operations/hosted_compute_ims.internal/resources

Also, we use [integration](https://thehub.github.com/epd/engineering/dev-practicals/observability/alerting/how-ninesapp-routes-alerts/) with Slack to report failed monitors to `#hosted-compute-ims-alerts` Slack channel

## Code examples

Two principles of our telemetry:
- `logger`, `statter`, `reporter` and `tracer` are singletons which can be called everywhere. No need to pass logger between methods and packages.
- using `context.Context` for storing logging and metrics fields. Since `ctx` is passed everywhere, we will never lose property and make sure that they are passed correctly through the chain of functions

### Logs and Error Reports

- Use `logger.Info`, `logger.Warn`, `logger.Error`, `logger.Fatal`, `logger.Debug` to send logs with different log level
- For errors, use:
    - `logger.ErrorWithReport(ctx, "failed to create image version", err)` to report error to Splunk and Sentry at the same time. Use it for server errors which should be investigated by us.
    - `logger.WithError(err).Error(ctx, "incorrect os_type")` to report error to Splunk only. Use it for user errors or expected errors which don't need to be investigated
    - Never use `reporter.Report(ctx, err)` because it reports Error to Sentry only. Skipping sending error to Splunk significantly complicates debugging of problem. There is no good use-case when you want to use this approach.
- Use `stash.WithLoggingFields` to save fields to context and make sure that they will be automatically included to all next logs
- If you need to access logger or base logger direcly, you can use `logger.GetLogger()`, `logger.GetBaseLogger()`, `reporter.GetReporter`, `reporter.GetBaseReporter`

```golang
import (
  "github.com/github/hosted-compute-ims/internal/telemetry/logger"
  "github.com/github/hosted-compute-ims/internal/telemetry/stash"
  "github.com/github/hosted-compute-ims/internal/telemetry/reporter"
)

func MyFunctionWhichSendsLogsAndErrorReports(ctx context.Context) {
    // sending info log to Splunk
    logger.Info(ctx, "info log") 

    // store fields in context
    ctx = stash.WithLoggingFields(ctx, kvp.String("job_name", "hello_world")) 

    // sending info log to Splunk, "job_name", "image_definition_id" and "image_version" will be included to log
    logger.Info(ctx, "info log with additional data",
        kvp.Uint64("image_definition_id", imageDefinitionId),
        kvp.String("image_version", imageVersion),
    )

    // sending error log with attached error
    logger.WithError(fmt.Errorf("test error")).Error(ctx, "log with attached error")

    // Also, the following functions are available: 
    // logger.Error, logger.Warn, logger.Debug, logger.Fatal

    // sending error to Splunk and report it to Sentry at the same time
    logger.ErrorWithReport(ctx, "failed to read database", err)
}
```

### Metrics

- Use `statter.Counter`, `statter.Increment`, `statter.Distribution`, `statter.DistributionMs`, `statter.Gauge`, `statter.Histogram`, `statter.Timing` to report metrics to Datadog
- Use `stash.WithStatterFields` to save fields to context and make sure that they will be automatically included to all next metrics
    - Be careful with fields which are attached to metrics. We should only include fields which are useful for data aggregation and avoid including fields which are related to specific job, e2eId, etc.
    - Usually, we attach properties like `image_type`, `job_name`, etc. Usually, we don't attach fields like `job_id`, `worker_id`, `image_version_id`, etc. 
- If you need to access statter or base statter direcly, you can use `statter.GetStatter()`, `statter.GetBaseStatter()`

```golang
import (
  "github.com/github/hosted-compute-ims/internal/telemetry/statter"
  "github.com/github/hosted-compute-ims/internal/telemetry/stash"
)

func MyFunctionWhichSendsMetrics(ctx context.Context) {
    // increment the single metric
    // use it when you want to track that some event happens
    // "1" is the count of events in this case
    statter.Increment(ctx, "function.start")

    // sending count-based metric with additional fields
    statter.Counter(ctx, "function.start", 3, kvp.String("function_name", "myfunc"))

    // sending value-based metric when you need to track statistical distributions
    statter.Distribution(ctx, "replicas.max_count", stats.Tags{"azure_region": "westus"}, 30)

    // sending timeline-based metric when you need to track duration of some process
    funcStartTime := time.Now()
    statter.DistributionMs(ctx, "function.duration", nil, time.Since(funcStartTime))

    // store fields in context
    ctx = stash.WithStatterFields(ctx, "job_name", "MyJob")

    // the event will have "job_name" field
    statter.Increment(ctx, "job.started")
}
```

### Traces

- Use `tracer.StartSpan` to start span. Use `span.End()` and `span.SetStatus` to control span.
- If you need to access tracer or base tracer direcly, you can use `tracer.GetTracer()`

```golang
import (
  "github.com/github/hosted-compute-ims/internal/telemetry/tracer"
)

func MyFunctionWhichSendsTraces(ctx context.Context) {
    spanCtx, span := tracer.StartSpan(ctx, "function1.start")
    defer span.End()
    // ...
    // use new context "spanCtx" instead of "ctx"
    // err = ...
    if err != nil {
        span.SetStatus(codes.Error, err.Error())
    }
}
```