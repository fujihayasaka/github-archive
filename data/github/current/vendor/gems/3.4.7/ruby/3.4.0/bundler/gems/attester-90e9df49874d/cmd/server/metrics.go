package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	httpexporter "github.com/github/go-exceptions/exporters/http"
	"github.com/github/go-exceptions/exporters/writer"
	"github.com/github/go-exceptions/stacktracers/pkgerrors"

	"github.com/github/go-stats"
	"github.com/github/go-stats/ps"
)

// setup StatsD metrics (Datadog)
// "127.0.0.1:28125" is the default DogStatsD address but Moda sets DOGSTATSD_HOST
// https://thehub.github.com/epd/engineering/products-and-services/internal/moda/feature-documentation/metrics/
func setupMetricsClient(config configStruct, log log.Logger) (stats.Client, error) {
	// Use io.Discard to discard statements unless DOGSTATSD_HOST or Debug logging is set
	sink := io.Discard
	if config.LogLevel == "debug" {
		sink = os.Stdout
	}

	// Set StatsD sink or log that it's disabled
	if config.DogStatsdHost != "" {
		sink = stats.UDPSink(config.DogStatsdHost)
	} else {
		log.Info("ATTESTER_DOGSTATSD_HOST is not set, metrics will not be sent")
	}

	// Create a new StatsD client and start it
	client := stats.NewClient(sink, time.Second, "attester").WithTags(stats.Tags{"deployed_to": config.AppEnv})
	client.Run() // Runs the StatsD client in a non-blocking manner

	return client, nil
}

func setupGoProfStats(mainCtx context.Context, client stats.Client, log log.Logger) {
	// setup and run the go-stats go-prof statistics in the background
	procStats := &ps.Reporter{Stats: client, Interval: time.Second * 15}
	go func() {
		if err := procStats.Run(mainCtx); err != nil {
			log.Error(fmt.Sprintf("procStats.Run returned an error: %s", err.Error()))
		}
	}()
}

// setupExceptionsReporter configures a new exceptions reporter for uncaught exceptions (Sentry)
func setupExceptionsReporter(appEnv string) (*exceptions.Reporter, error) {
	var err error
	var exporter exceptions.Exporter = writer.NewExporter(os.Stdout)

	// go-exceptions/http expects the FAILBOT_HAYSTACK_URL to be set in production
	_, ok := os.LookupEnv("FAILBOT_HAYSTACK_URL")
	if ok {
		exporter, err = httpexporter.NewExporter()
		if err != nil {
			return nil, err
		}
		log.Info("FAILBOT_HAYSTACK_URL is set, sending exceptions to failbot")
	} else {
		log.Error("FAILBOT_HAYSTACK_URL is not set, discarding exceptions")
	}

	reporter, err := exceptions.NewReporter(
		exceptions.WithExporter(exporter),
		exceptions.WithApplication("attester"),
		exceptions.WithStacktraceFunc(pkgerrors.NewStackTracer()),
		exceptions.WithValues(map[string]string{
			"deployed_to": appEnv,
			"release":     GitCommit,
		}),
	)
	if err != nil {
		return nil, err
	}

	return reporter, nil
}
