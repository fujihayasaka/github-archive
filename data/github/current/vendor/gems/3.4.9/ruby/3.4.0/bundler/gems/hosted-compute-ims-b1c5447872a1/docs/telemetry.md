# Telemetry

There are 4 types of telemetry in IMS:
- Logs (Splunk)
- Error reports (Sentry)
- Traces (Datadog)
- Metrics (Datadog)

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

- Dashboard: https://app.datadoghq.com/dashboard/vwb-6j5-4ry
- Monitors: https://app.datadoghq.com/monitors/manage?q=service%3A%22hosted-compute-ims%22&order=desc
- Traces: https://app.datadoghq.com/apm/services/hosted-compute-ims/operations/hosted_compute_ims.internal/resources

Also, we use [integration](https://thehub.github.com/epd/engineering/dev-practicals/observability/alerting/how-ninesapp-routes-alerts/) with Slack to report failed monitors to `#hosted-compute-ims-alerts` Slack channel

## Code examples

### Logs and Error Reports
```golang
func MyFunctionWhichSendsLogsAndErrorReports(logger *telemetry.ReportingLogger) {
    // sending info log to Splunk
    logger.Info("info log")
    // ...
    // err = ...
    if err != nil {
        // sending error to Splunk
        logger.WithError(err).Error("error log")

        // sending error to Sentry and sending error to splunk at the same time.
        // always prefer this option unless you don't want to send error to Sentry intentionally
        logger.ErrorWithReport("error log and sentry error", err)
    }

    // all logger methods support providing additional metadata to info or error
    logger.Info("info log with additional data",
        kvp.Uint64("image_definition_id", imageDefinitionId),
        kvp.String("image_version", imageVersion),
    )
}
```

### Metrics
```golang
func MyFunctionWhichSendsMetrics(logger *telemetry.ReportingLogger) {
    // sending count-based metric without additional tags
    // use it when you want to track that some event happens
    // "1" is the count of events in this case
    logger.Stats.Counter("function.start", nil, 1)

    // sending count-based metric with additional tags
    logger.Stats.Counter("function.start", stats.Tags{"my_property": "my_value"}, 1)

    // sending value-based metric when you need to track statistical distributions
    logger.Stats.Distribution("replicas.max_count", stats.Tags{"azure_region": "westus"}, 30)

    // sending timeline-based metric when you need to track duration of some process
    funcStartTime := time.Now()
    logger.Stats.DistributionMs("function.duration", nil, time.Since(funcStartTime))
}
```


### Traces

```golang
func MyFunctionWhichSendsTraces(ctx context.Context, telem *telemetry.Telemetry) {
    spanCtx, span := telem.Tracer.Tracer.Start(ctx, "function1.start")
    defer span.End()
    // ...
    // use new context "spanCtx" instead of "ctx"
    // err = ...
    if err != nil {
        span.SetStatus(codes.Error, err.Error())
    }
}
```