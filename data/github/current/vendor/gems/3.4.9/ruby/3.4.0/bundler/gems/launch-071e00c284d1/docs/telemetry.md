# Launch telemetry
- Use semantic conventions [^4] whenever possible. Launch is not in compliance with semantic conventions for its telemetry, but its a best practice moving forward.

## Metrics

- For new metrics, avoid using [`Histogram`](https://github.com/github/launch/blob/fb95296f09af14359e8da15c9e2860eb7f7e839b/observability/statter/statter.go#L109-L112) and [`LegacyTiming`](https://github.com/github/launch/blob/fb95296f09af14359e8da15c9e2860eb7f7e839b/observability/statter/statter.go#L131-L134). [`Distribution`](https://github.com/github/launch/blob/fb95296f09af14359e8da15c9e2860eb7f7e839b/observability/statter/statter.go#L114-L118) or [`Timing`](https://github.com/github/launch/blob/fb95296f09af14359e8da15c9e2860eb7f7e839b/observability/statter/statter.go#L120-L124) (distribution-based) should be used instead. See https://github.com/github/c2c-actions-experience/issues/5420.
- Prefer fewer metrics tags, with higher-dimensionality[^3]. This aids in discoverability and makes the overall metrics topology of Launch simpler to reason about.
- Be careful about introducing high-cardinality[^2] tags. DataDog makes these extremely expensive from a billing perspective. [^1]

## Logging

- Durations are logged to Splunk and [Kusto](https://github.com/orgs/github/teams/c2c-actions/discussions/487) in seconds. See https://github.com/github/launch/pull/4354.
- Use semantic conventions [^4] whenever possible. Launch is not in compliance with semantic conventions for its telemetry, but its a best practice moving forward.
- Unlike in the case of metrics, we should strive for high-cardinality fields when logging. Correlating events is only possible if there is enough cardinality within the log event to do so. (Examples of the most useful correlation ids are in `observability/ctxstash/correlation.go`. [^5])

## Dev Environment
### Distributed Tracing

To test tracing changes:

1. Visit https://app.lightstep.com/github-prod/developer-mode to set up a satellite.
2. Uncomment [the OpenTracing settings in `script/_serverenv`](https://github.com/github/launch/blob/8d60db5c405357c917fc9cc5ea5dd6e97530f4a7/script/_serverenv#L313-L316)
3. Stop and restart the Launch service (`service launch restart`)

For more info, see https://thehub.github.com/epd/engineering/dev-practicals/observability/distributed-tracing/

### Metrics

Prometheus is used as a means of visualizing metrics in development environments and is accessible
at http://localhost:9091. You'll need to run `script/docker-compose up -d prom` in order to start
the containers.

When starting Launch, you'll need to use `script/server --prom`

### Logging

You can follow logs using `tail -f output.log*`

[^1]: https://docs.datadoghq.com/account_management/billing/custom_metrics/?tab=countrate&tabs=countrate
[^2]: https://docs.honeycomb.io/getting-started/high-cardinality/#what-is-cardinality
[^3]: https://docs.honeycomb.io/getting-started/high-cardinality/#what-is-dimensionality
[^4]: https://github.com/github/github-semantic-conventions/blob/main/combined-docs/github-index.md
[^5]: https://github.com/github/launch/blob/master/observability/ctxstash/correlation.go
