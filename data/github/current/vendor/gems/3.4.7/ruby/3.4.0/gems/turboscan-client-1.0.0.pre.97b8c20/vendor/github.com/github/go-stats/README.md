# go-stats

A DataDog-compatible StatsD client that supports buffering, async reporting, downsampling, tagging, and reports a metric in ~650ns and with 0 bytes allocated on the heap. This is a very important feature.

### Versions of Note

* To ensure that your service has Custom Metric Attribution enabled, you must use a go-stats version >=1.16.1
* To track metric emission success rates from your service, you need go-stats version >=1.18.0. That version emits internal metrics that report on metric delivery success rates.

## Usage

1. In a Moda app, configure `STATS_ADDR` to the address of the datadog agent. Heaven [automatically sets](https://thehub.github.com/epd/engineering/products-and-services/internal/moda/reference/environment-variables/#default-environment-variables) `KUBE_NODE_HOSTNAME` to the node's FQDN.

```yaml
containers:
  - name: my-rad-mu-service
    env:
      - name: STATS_ADDR
        value: "$(KUBE_NODE_HOSTNAME):28125"
```

2. Enable [unified service tagging](https://thehub.github.com/epd/engineering/dev-practicals/observability/metrics/metric-naming/#datadog-unified-service-tagging)

3. Initialize, start, and use the stats client

```go
func main() {
  var sink = io.Discard // Use io.Discard to discard statements, or use os.Stdout to report to Stdout.

  if statsdAddr := os.Getenv("STATSD_ADDR"); statsdAddr != "" {
    sink = stats.UDPSink(statsdAddr)
  }

  client := stats.NewClient(sink, time.Second, "")
  client.Run()        // Runs the client in a non-blocking manner
  defer client.Stop() // Ensure the client will stop running before the function returns
}

func handleRequest(sc stats.Client) {
  client.Counter("requests", stats.Tags{"key": "value"}, int64(1)) // increment a metric with tags
}
```

See the runnable example in [example_test.go](./example_test.go) for more complete examples of how to use the `go-stats` package.

## Configuring Buffer Size

The go-stats package uses a channel to collect and emit metrics to the datadog-agent over UDP. The default max channel size is `2048`, but you can use the `WithChannelSize` function when you initialize the go-stats client to up or downsize.

If you need to further optimize the performance of this already light-weight package, consider decreasing the max channel size, which will reduce memory allocation.

If your service is dropping metrics at an unacceptable rate, consider increasing the max channel size.

```golang
std := stats.NewClient(sink, time.Second, "", WithChannelSize(32))
```

## Metric Delivery Success Rate Reporting

By default, the go-stats package reports two counter metrics:

* `go-stats.metrics`: A count of the metrics successfully enqueued to be sent to the DogstatsD agent over UDP.
* `go-stats.metric_dropped_on_receive`: A count of the metrics dropped because the channel for collecting metrics to emit is full.

You can observe the metric delivery success rate of your service in [this](https://app.datadoghq.com/s/59fe6c40c/zj5-rqi-9bc) Datadog dashboard. Scope the graphs by `kube_namespace`, if your service tags metrics with `kube_namespace`, or `gh.telemetry_owner`. The `gh.telemetry_owner` tag will be enabled on all Moda services after [this](https://github.com/github/observability-experience/issues/284) rollout is complete.

The emission of these metrics does not noticeably impact the performance of services using the `go-stats` package, as measured by k8s resource consumption. However, if you have a service that must fine tune for very high performance, you can disable the emission of either or both of theese metrics by initalizing the `go-stats` client with the `WithoutChannelExceededReporting` or `WithoutTotalMetricsReporting` options, like this:

```golang
std := stats.NewClient(sink, time.Second, "", WithoutChannelExceededReporting(), WithoutTotalMetricsReporting())
```

## GHES Wrapper

On GHES (only), you should wrap your stats client with `stats.NewCollectdClient`.  GHES uses
collectd instead of DataDog, which requires using timing metrics instead of distribution metrics and
does not support tags at all. Wrapping your client will handle the conversions for you:

```go
// ...in your main()
client := stats.NewClient(sink, time.Second, "")
if weAreInGHES {
 client = stats.NewCollectdClient(client)
}
// ...do everything else like you normally would
```

If your code run on GHES and dotcom environments and it calls stats client `WithTags` function, make sure it happens after the `stats.NewCollectdClient` function call.

This example will not work correctly :x:

```go
client := stats.NewClient(sink, time.Second, "")
client = client.WithTags(stats.Tags{"env": "my-env"})
if weAreInGHES {
 client = stats.NewCollectdClient(client)
}
```

This example will work correctly :white_check_mark:

```go
client := stats.NewClient(sink, time.Second, "")
if weAreInGHES {
 client = stats.NewCollectdClient(client)
}

client = client.WithTags(stats.Tags{"env": "my-env"})
```

## Extending the stats reporter

The stats package comes with multiple sub packages that let you report statistics:

* `go-stats/ps`: reports process and runtime metrics. Process metrics are reported as `<prefix.>.proc.*` and runtime metrics are reported as `runtime.go.*`. The runtime metrics can be viewed in the [Go Runtime Metrics dashboard](https://app.datadoghq.com/dash/integration/apm_go) and in the [APM service overview](https://thehub.github.com/epd/engineering/dev-practicals/observability/distributed-tracing/user-guide/usage-overview/#the-service-catalog).
* `go-stats/db`: reports database/sql stastistics

> [!NOTE]
> Go runtime metrics requires unified service tagging for metrics, which must be configured using one of [the approaches on thehub](https://thehub.github.com/epd/engineering/dev-practicals/observability/metrics/metric-naming/#datadog-unified-service-tagging).

To use them, initialize your `stats` client and then use in your `main` package. Below is an example for the `go-stats/ps` package:

```go
package main

import (
 "context"
 "os"
 "syscall"
 "time"

 "github.com/github/go-ctxutil/sigctx"
 "github.com/github/go-stats"
 "github.com/github/go-stats/ps"
)

func main() {
 // use the go-ctxutil to cancel the context on certain signals
 ctx := sigctx.WithSignal(context.Background(), syscall.SIGINT, syscall.SIGTERM)
 appName := "insights"
 client := stats.NewClient(os.Stdout, time.Second, "")
 client.Run()        // Runs the client in a non-blocking manner
 defer client.Stop() // Ensure the client will stop running before the function returns

 // run the procStats in the background
 procStats := &ps.Reporter{
  Stats:    client,
  Interval: time.Second * 5,
 }
 go procStats.Run(ctx)

}
```

## One `Client` per process

The `stats.Client` writes to the sink (`os.Stdout` in the example above) without synchronization, so you should not construct multiple Clients with the same sink.
In practice this means you should use one Client throughout your application.
