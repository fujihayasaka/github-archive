// Package root holds the command reposvc which is the entry point
// for processing Repository metadata updates.
package root

import (
	"context"

	"github.com/github/turboscan/ts/hydro/publishers"

	"github.com/github/turboscan/ts/mysql/managedanalysis"

	"github.com/github/turboscan/ts/enabled_status"

	"github.com/github/turboscan/ts/mysql/repository"

	"github.com/github/turboscan/ts/appctx"
	"github.com/spf13/cobra"

	"github.com/github/turboscan/ts/app"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/hydro/consumers"
)

const svcName = "reposvc"

var RepoSvcCmd = &cobra.Command{
	Use:   svcName,
	Short: "reposvc starts the repo service which is the entry point for processing repository metadata updates.",
	Long: `reposvc starts the repo service which is the entry point for processing repository metadata updates.
`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return app.RunServiceFunc(svcName, serviceFunc)
	},
}

func serviceFunc(ctx context.Context, cfg *config.Config) (app.Server, app.CleanupFunc, error) {
	logger, statter := appctx.Logger(ctx), appctx.Stats(ctx)

	var cleanup app.Cleaner
	kc, err := cfg.NewKafkaConfig(logger, statter)
	if err != nil {
		return nil, cleanup.Clean, err
	}

	publisher, err := publishers.New(*kc, statter)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	cleanup.Append(publisher.Close)

	db, closeDB, err := app.NewDB(ctx, cfg)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	cleanup.Append(closeDB)

	alertService, err := app.NewAlertService(db)
	if err != nil {
		return nil, cleanup.Clean, err
	}

	es, err := app.NewES(ctx, cfg)
	if err != nil {
		return nil, cleanup.Clean, err
	}

	repoService := repository.NewService(db)
	enabledService := enabled_status.NewEnabledStatusService(db, alertService, repoService, managedanalysis.NewService(db, publisher), publisher, true)

	rp := consumers.NewRepoEventProcessor(repoService, enabledService, alertService, es)

	// We want to start consuming from the newest offset instead of the beginning of the topic
	server, err := consumers.NewConsumerServer(*kc, cfg.KafkaGroup, rp, logger, consumers.ConsumeFromNewestOffset)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	return server, cleanup.Clean, nil
}
