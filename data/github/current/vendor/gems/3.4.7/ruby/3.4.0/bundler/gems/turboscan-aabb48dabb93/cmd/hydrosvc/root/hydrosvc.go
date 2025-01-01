// Package root is the command entry point for ingesting Deliveries by processing messages from the NewAnalysis hydro topic.
package root

import (
	"context"
	"time"

	"github.com/github/turboscan/ts/mysql/delivery"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/hydro/consumers"

	"github.com/spf13/cobra"

	"github.com/github/turboscan/ts/app"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
)

const svcName = "hydrosvc"

var HydroSvcCmd = &cobra.Command{
	Use:   svcName,
	Short: "Starts the service which is the entry point for ingesting Deliveries by processing messages from the NewAnalysis hydro topic",
	Long:  "Starts the service which is the entry point for ingesting Deliveries by processing messages from the NewAnalysis hydro topic.",
	RunE: func(cmd *cobra.Command, args []string) error {
		return app.RunServiceFunc(svcName, serviceFunc)
	},
}

func serviceFunc(ctx context.Context, cfg *config.Config) (app.Server, app.CleanupFunc, error) {
	logger, statter := appctx.Logger(ctx), appctx.Stats(ctx)

	var cleanup app.Cleaner

	maxRetryElapsedTime := 200 * time.Second
	if cfg.IsEnterpriseEnv() {
		// On GHES an analysis we can't process will block all processing so it makes sense to not retry it for so long.
		maxRetryElapsedTime = 60 * time.Second
	}

	kc, err := cfg.NewKafkaConfig(logger, statter)
	if err != nil {
		return nil, cleanup.Clean, err
	}

	db, closeDB, err := app.NewDB(ctx, cfg)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	cleanup.Append(closeDB)

	aqueductClient, err := aqueduct.NewClient(cfg, logger, statter, nil)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	ap := consumers.NewAnalysisEventProcessor(aqueductClient, delivery.NewService(db), maxRetryElapsedTime)
	server, err := consumers.NewConsumerServer(*kc, cfg.KafkaGroup, ap, logger)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	return server, cleanup.Clean, nil
}
