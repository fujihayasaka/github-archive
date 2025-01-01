package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	statsDB "github.com/github/go-stats/db"
	"github.com/github/go-stats/ps"
	"github.com/github/trust-metadata-api/pkg/storage"
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
		log.Info("TMA_DOGSTATSD_HOST is not set, metrics will not be sent")
	}

	// Create a new StatsD client and start it
	client := stats.NewClient(sink, time.Second, "trust_metadata_api").WithTags(stats.Tags{"deployed_to": config.AppEnv})
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

func setupDBStats(mainCtx context.Context, client stats.Client, config configStruct, db *storage.DatabaseEndpoints, log log.Logger) {
	if config.Backend == "mysql" {
		// setup and run the go-stats database statistics in the background
		dbClient := client.WithTags(stats.Tags{
			"db_role": "primary",
		})
		dbStats := &statsDB.Reporter{
			Stats:    dbClient,
			Interval: time.Second * 15,
			DB:       db.Primary.GetDB(),
		}
		go func() {
			if err := dbStats.Run(mainCtx); err != nil {
				log.Error(fmt.Sprintf("dbStats.Run returned an error: %s", err.Error()))
			}
		}()

		// If a replica is configured, monitor that too
		if db.Primary != db.Replica {
			dbClient := client.WithTags(stats.Tags{
				"db_role": "replica",
			})
			roStats := &statsDB.Reporter{
				Stats:    dbClient,
				Interval: time.Second * 15,
				DB:       db.Replica.GetDB(),
			}
			go func() {
				if err := roStats.Run(mainCtx); err != nil {
					log.Error(fmt.Sprintf("roStats.Run returned an error: %s", err.Error()))
				}
			}()
		}
	}
}
