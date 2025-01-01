// Package root provides the service that powers expectedcodeqlrunprocessorsvc
package root

import (
	"context"

	"github.com/github/turboscan/ts/app"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/hydro/consumers"
	"github.com/github/turboscan/ts/hydro/publishers"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/spf13/cobra"
)

const svcName = "expectedcodeqlrunprocessorsvc"

var ExpectedCodeqlRunProcessorCmd = &cobra.Command{
	Use:   svcName,
	Short: "Consumes events from the Hydro which was emitted by the default setup runs from push and pr events",
	Long:  "Consumes events from the Hydro which was emitted by the default setup runs from push and pr events.",
	RunE: func(cmd *cobra.Command, args []string) error {
		return app.RunServiceFunc(svcName, serviceFunc)
	},
}

func serviceFunc(ctx context.Context, cfg *config.Config) (app.Server, app.CleanupFunc, error) {
	logger, statter := appctx.Logger(ctx), appctx.Stats(ctx)

	kc, err := cfg.NewKafkaConfig(logger, statter)
	var cleanup app.Cleaner
	if err != nil {
		return nil, cleanup.Clean, err
	}

	db, closeDB, err := app.NewDB(ctx, cfg)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	cleanup.Append(closeDB)

	publisher, err := publishers.New(*kc, statter)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	cleanup.Append(publisher.Close)

	p := consumers.NewExpectedCodeqlRunProcessor(managedanalysis.NewService(db, publisher), repository.NewService(db))

	// We want to start consuming from the newest offset instead of the beginning of the topic
	consumer, err := consumers.NewConsumerServer(*kc, cfg.KafkaGroup, p, logger, consumers.ConsumeFromNewestOffset)
	if err != nil {
		return nil, cleanup.Clean, err
	}

	return consumer, cleanup.Clean, nil
}
