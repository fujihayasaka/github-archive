> With the recent reorg, `Frameworks-Containers` team has been dissolved. Starting from 5th June 2023, we are part of Ecosystem-Events team. We continue to own and provide support for the charter owned by the `Frameworks-Containers` team, but we are not working on any new feature developments.

# go-stats

A DataDog-compatible StatsD client that does
buffering, async reporting, downsampling and tagging. The main "feature" of
this client is that it can report a metric in ~650ns and allocating 0 bytes
on the heap. This is a very important feature.

## Usage

* Initialize the client with a sink that conforms to the `io.Writer` interface
* Run the client
* Use the client
* Stop the client

Let's say you have a `main` function that runs your app:

```go
package main

import (
 "github.com/github/my-app/server"
)

func main() {
 Server.Start()
}
```

You could utilize the statsd client like this:

```go
package main

import (
 "io"
 "os"
 "time"

 "github.com/github/go-stats"
)

func main() {
 var sink = io.Discard // Use io.Discard to discard statements, or use os.Stdout to report to Stdout.

 if statsdAddr := os.Getenv("STATSD_ADDR"); statsdAddr != "" {
  sink = stats.UDPSink(statsdAddr)
 }

 // Use your app here. Your metrics will be prefixed with this
 // value in datadog: "insights.requests"
 appName := "insights"
 client := stats.NewClient(sink, time.Second, appName)
 client.Run()        // Runs the client in a non-blocking manner
 defer client.Stop() // Ensure the client will stop running before the function returns
 Server.Start()
}

func handleRequest(sc stats.Client) {
 client.Counter("requests", stats.Tags{"key": "value"}, int64(1)) // Example of using the `Counter` function to increment a metric with tags
}

```

*Note that this is a basic example but in reality, you would want to consider setting up your `main` function such that it traps the program's exit signal and handles it appropriately. Otherwise, a panic would crash the program and your `defer` statement won't run*.

## Configuring Buffer Size

The go-stats package uses a channel to collect and emit metrics to the datadog-agent over UDP. The default max channel size is `2048`, but you can use the `WithChannelSize` function when you initialize the go-stats client to up or downsize.

If you need to further optimize the performance of this already light-weight package, consider decreasing the max channel size, which will reduce memory allocation.

If your service is dropping metrics at an unacceptable rate, consider increasing the max channel size.

```golang
std := stats.NewClient(sink, time.Second, appName, WithChannelSize(32))
```

## Reporting when metrics are dropped

By default, the go-stats package reports two counter metrics:

* `go-stats.metrics`: A count of the metrics successfully enqueued to be sent to the DogstatsD agent over UDP.
* `go-stats.metric_dropped_on_receive`: A count of the metrics dropped because the channel for collecting metrics to emit is full.

The emission of these metrics does not noticeably impact the performance of services using the `go-stats` package, as measured by k8s resource consumption. However, if you have a service that must fine tune for very high performance, you can disable the emission of either or both of theese metrics by initalizing the `go-stats` client with the `WithoutChannelExceededReporting` or `WithoutTotalMetricsReporting` options, like this:

```golang
std := stats.NewClient(sink, time.Second, appName, WithoutChannelExceededReporting(), WithoutTotalMetricsReporting())
```

## GHES Wrapper

On GHES (only), you should wrap your stats client with `stats.NewCollectdClient`.  GHES uses
collectd instead of DataDog, which requires using timing metrics instead of distribution metrics and
does not support tags at all. Wrapping your client will handle the conversions for you:

```go
// ...in your main()
client := stats.NewClient(sink, time.Second, "insights")
if weAreInGHES {
 client = stats.NewCollectdClient(client)
}
// ...do everything else like you normally would
```

If your code run on GHES and dotcom environments and it calls stats client `WithTags` function, make sure it happens after the `stats.NewCollectdClient` function call.

This example will not work correctly :x:

```go
client := stats.NewClient(sink, time.Second, "insights")
client = client.WithTags(stats.Tags{"env": "my-env"})
if weAreInGHES {
 client = stats.NewCollectdClient(client)
}
```

This example will work correctly :white_check_mark:

```go
client := stats.NewClient(sink, time.Second, "insights")
if weAreInGHES {
 client = stats.NewCollectdClient(client)
}

client = client.WithTags(stats.Tags{"env": "my-env"})
```

## Extending the stats reporter

The stats package comes with multiple sub packages that let you report statistics:

* `go-stats/ps`: reports process statistics
* `go-stats/db`: reports database/sql stastistics

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
  appName :=  "insights"
 client := stats.NewClient(os.Stdout, time.Second, appName)
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

## Contributing

 To learn more about developing and making updates to this repo, please checkout [the contributing guide](https://github.com/github/frameworks-containers/tree/main/docs/go-libs-common-docs/CONTRIBUTING.md).
