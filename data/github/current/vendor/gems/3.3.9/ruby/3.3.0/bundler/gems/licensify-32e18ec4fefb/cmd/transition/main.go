// This is the main entry point for running transitions against the licensify data in CosmosDB
package main

import (
	"context"
	"flag"
	"fmt"
	"os"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	"github.com/github/licensify/internal/aqueduct"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/transitions"
)

var dryRun = flag.Bool("dry_run", true, "whether to run the transition in dry run mode")
var transitionName = flag.String("name", "", "the name of the transition to run")
var startCustomerID = flag.Uint64("start_customer_id", 0, "the customer ID to start the transition from")
var endCustomerID = flag.Uint64("end_customer_id", 0, "the customer ID to end the transition at")

func main() {
	if err := runTransition(); err != nil {
		fmt.Printf("failed to run the transition: %v\n", err)
		os.Exit(1)
	}
}

func runTransition() error {
	flag.Parse()

	cfg, err := config.Load()
	if err != nil {
		fmt.Printf("Failed loading config: %v\n", err)
		return err
	}

	ctx := context.Background()
	telem, err := telemetry.NewFromEnv()
	if err != nil {
		return fmt.Errorf("failed to configure telemetry: %w", err)
	}
	defer func() {
		if err := telem.Shutdown(ctx); err != nil {
			fmt.Printf("failed to shutdown telemetry: %v\n", err)
		}
	}()

	logger := cfg.ConfigureLogger(telem.Logger, cfg.ServiceName).Named("transition")

	logger.Info("Initializing transition job...",
		kvp.String("gh.licensify.transition.name", *transitionName),
		kvp.Bool("gh.licensify.transition.dry_run", *dryRun),
	)

	statter := cfg.StatsClient()
	statter = statter.WithTags(stats.Tags{"env": cfg.HeavenEnv, "process.executable.name": "transition"})

	logger.Info("starting statsd client")
	statter.Run()
	defer statter.Stop()

	aqueductClient, err := aqueduct.NewClient(
		cfg.AqueductURL,
		cfg.AqueductAPIKey,
		cfg.AqueductAPIKeyVersion,
		statter,
	)
	if err != nil {
		return fmt.Errorf("failed to create aqueduct client: %w", err)
	}

	switch *transitionName {
	case "add_license_status":
		return transitions.NewAddLicenseStatusTransition(cfg, logger, aqueductClient).Run(ctx, *startCustomerID, *endCustomerID, *dryRun)
	default:
		return nil
	}
}
