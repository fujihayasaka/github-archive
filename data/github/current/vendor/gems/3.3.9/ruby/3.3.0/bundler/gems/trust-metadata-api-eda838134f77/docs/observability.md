# Observability

For general observability at GitHub, see [The Hub - Observability](https://thehub.github.com/epd/engineering/dev-practicals/observability/)

## Moda Homepage

Moda resources can be found on the [Moda homepage](https://moda.githubapp.com/apps/trust-metadata-api) including links to DataDog dashboards.

## Datadog

Datadog is used for monitoring and alerting. The following dashboards are available:

- [Trust Metadata API](https://app.datadoghq.com/dashboard/p5b-5gt-v76/trust-metadata-api)

Datadog resources are managed via the [github/datadog-monitoring](https://github.com/github/datadog-monitoring) repo. If you need to make changes to the monitors you will need to make a PR to that repo. Documentation can be found on [The Hub - Datadog](https://thehub.github.com/epd/engineering/dev-practicals/observability/metrics/dashboards/dashboards/).

The basic workflow is:

- Make the changes to the dashboard in the Datadog Web UI
- Run the `.ddimport` command in `#package-security-ops` slack channel
- Make a pull request to the [github/datadog-monitoring repo](https://github.com/github/datadog-monitoring) in the `config/services/trust-metadata-api` directory
- Deploy the changes for the `datadog-monitoring` repo

The `github/datadog-monitoring` repo automatically backs up org-wide dashboards
so we don't need to add the TMA dashboard.

The file is located here:
https://github.com/github/datadog-monitoring/blob/main/config/org-wide/dashboards/trust-metadata-api-p5b-5gt-v76.yaml

### Metrics

The following metrics are emitted from the Trust Metadata API service. All
metrics are prefixed with `trust_metadata_api` and tagged with a `deployed_to`
value indicating the deployment environment.

#### Process Stats

Originating from the
[`go-stats/ps`](https://github.com/github/go-stats/blob/main/ps/procstats.go)
reporter:

| metric                                                                                                                                                                 | type  |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- |
| [`proc.goroutines`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.proc&metric=trust_metadata_api.proc.goroutines)                                 | Gauge |
| [`proc.memory.allocated`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.proc&metric=trust_metadata_api.proc.memory.allocated)                     | Gauge |
| [`proc.memory.mallocs`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.proc&metric=trust_metadata_api.proc.memory.mallocs)                         | Gauge |
| [`proc.memory.frees`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.proc&metric=trust_metadata_api.proc.memory.frees)                             | Gague |
| [`proc.memory.heap`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.proc&metric=trust_metadata_api.proc.memory.heap)                               | Gauge |
| [`proc.memory.stack`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.proc&metric=trust_metadata_api.proc.memory.stack)                             | Gauge |
| [`proc.memory.gc.total_pause`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.proc&metric=trust_metadata_api.proc.memory.gc.total_pause)           | Gague |
| [`proc.memory.gc.pause_per_second`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.proc&metric=trust_metadata_api.proc.memory.gc.pause_per_second) | Gauge |

#### DB Stats

Originating from the
[`go-stats/db`](https://github.com/github/go-stats/blob/main/db/dbstats.go)
reporter:

| metric                                                                                                                                                           | type    |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| [`db.sql.max_open_connections`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.db.sql&metric=trust_metadata_api.db.sql.max_open_connections) | Gauge   |
| [`db.sql.open_connections`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.db.sql&metric=trust_metadata_api.db.sql.open_connections)         | Gauge   |
| [`db.sql.idle`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.db.sql&metric=trust_metadata_api.db.sql.idle)                                 | Gauge   |
| [`db.sql.in_use`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.db.sql&metric=trust_metadata_api.db.sql.in_use)                             | Gauge   |
| [`db.sql.max_idle_closed`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.db.sql&metric=trust_metadata_api.db.sql.max_idle_closed)           | Counter |
| [`db.sql.max_idle_time_closed`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.db.sql&metric=trust_metadata_api.db.sql.max_idle_time_closed) | Counter |
| [`db.sql.max_lifetime_closed`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.db.sql&metric=trust_metadata_api.db.sql.max_lifetime_closed)   | Counter |
| [`db.sql.wait_count`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.db.sql&metric=trust_metadata_api.db.sql.wait_count)                     | Counter |
| [`db.sql.wait_duration`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.db.sql&metric=trust_metadata_api.db.sql.wait_duration)               | Counter |

#### Twirp Stats

Originating from the
[`go-twirp/server/hooks/stats`](https://github.com/github/go-twirp/blob/main/server/hooks/stats/request_metrics.go)
reporter:

| metric                                                                                                                                                     | type         | tags                                            |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------ | ----------------------------------------------- |
| [`request_count`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.re&metric=trust_metadata_api.request_count)                           | Counter      | `twirp_service`                                 |
| [`request_duration`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.re&metric=trust_metadata_api.request_duration)                     | Distribution | `twirp_service`, `twirp_method`, `twirp_status` |
| [`response_sent_duration`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.re&metric=trust_metadata_api.response_sent_duration)         | Distribution | `twirp_service`, `twirp_method`, `twirp_status` |
| [`response_prepared_duration`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.re&metric=trust_metadata_api.response_prepared_duration) | Distribution | `twirp_service`, `twirp_method`                 |

#### HTTP Stats

Originating from the
[`go-stats/http`](https://github.com/github/go-stats/blob/main/http/http.go)
reporter:

| metric                                                                                                                                   | type         | tags                     |
| ---------------------------------------------------------------------------------------------------------------------------------------- | ------------ | ------------------------ |
| [`response_count`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.re&metric=trust_metadata_api.response_count)       | Counter      | `http.path`, `http.code` |
| [`response_duration`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.re&metric=trust_metadata_api.response_duration) | Distribution | `http.path`, `http.code` |
| [`response_size`](https://app.datadoghq.com/metric/summary?filter=trust_metadata_api.re&metric=trust_metadata_api.response_size)         | Distribution | `http.path`, `http.code` |

## Logs - Splunk

Logs can be found in [Splunk](https://splunk.githubapp.com/) in the `trust-metadata` index:

```text
index IN(trust-metadata) kube_namespace=trust-metadata-api-*
```

## App Errors - Sentry

Exceptions are sent to [Sentry](https://sentry.io/organizations/github/projects/trust-metadata-api/?project=4504079440740352)

## Distributed tracing

Tracing can be viewed in Datadog
[prod](https://app.datadoghq.com/apm/services/trust-metadata-api/operations/github_com_github_trust_metadata_api_o_11_y.internal/resources?dependencyMap=qson%3A%28data%3A%28isAccordionOpen%3A%21f%29%2Cversion%3A%210%29&env=production&groupMapByOperation=null&resources=qson%3A%28data%3A%28visible%3A%21t%2Chits%3A%28selected%3Atotal%29%2Cerrors%3A%28selected%3Atotal%29%2Clatency%3A%28selected%3Aavg%29%2CtopN%3Aall%29%2Cversion%3A%210%29&summary=qson%3A%28data%3A%21f%2Cversion%3A%211%29&topGraphs=latency%3Alatency%2Chits%3Aversion_count%2Cerrors%3Aversion_count%2CbreakdownAs%3Apercentage&start=1696978087941&end=1696981687941&paused=false), [staging](https://app.datadoghq.com/apm/services/trust-metadata-api/operations/github_com_github_trust_metadata_api_o_11_y.internal/resources?dependencyMap=qson%3A%28data%3A%28isAccordionOpen%3A%21f%29%2Cversion%3A%210%29&env=staging&groupMapByOperation=null&resources=qson%3A%28data%3A%28visible%3A%21t%2Chits%3A%28selected%3Atotal%29%2Cerrors%3A%28selected%3Atotal%29%2Clatency%3A%28selected%3Aavg%29%2CtopN%3Aall%29%2Cversion%3A%210%29&summary=qson%3A%28data%3A%21f%2Cversion%3A%211%29&topGraphs=latency%3Alatency%2Chits%3Aversion_count%2Cerrors%3Aversion_count%2CbreakdownAs%3Apercentage&start=1696978087941&end=1696981687941&paused=false)
(Login via Okta)

### Distributed tracing - Development Mode

To test tracing locally and collect traces from your local machine.

Run the trace server locally

```sh
docker run --rm --name jaeger \
  -e COLLECTOR_ZIPKIN_HOST_PORT=:9411 \
  -p 6831:6831/udp \
  -p 6832:6832/udp \
  -p 5778:5778 \
  -p 16686:16686 \
  -p 4317:4317 \
  -p 4318:4318 \
  -p 14250:14250 \
  -p 14268:14268 \
  -p 14269:14269 \
  -p 9411:9411 \
  jaegertracing/all-in-one:1.49
```

Start the local TMA server pointing to the Docker OTEL Collector:

```sh
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:4318/v1/traces
```

Visit the Jaeger UI at `http://localhost:16686`

## Azure PagerDuty Integrations

Each Azure service we have enabled alerts on must have a corresponding
service on PagerDuty. This allows us to route alerts from Azure. Below is a list of all Azure PagerDuty integration services for reference:

- [Staging Trust Metadata API Blob Storage](https://github.pagerduty.com/service-directory/PKON8YW?)
- [Production Trust Metadata API Blob Storage](https://github.pagerduty.com/service-directory/P1M9BQY?) (currently disabled until we are ready to enable blob storage in production)
