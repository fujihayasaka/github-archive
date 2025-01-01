// Package root provides the service that powers alertlinkprocessorsvc
package root

import (
	"context"

	"github.com/github/turboscan/ts/alertlinks"
	"github.com/github/turboscan/ts/mysql/alertlink"

	"github.com/github/turboscan/ts/appctx"

	"github.com/spf13/cobra"

	"github.com/github/turboscan/ts/app"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/hydro/consumers"
	"github.com/github/turboscan/ts/hydro/publishers"
)

const svcName = "alertlinkprocessorsvc"

var AlertLinkCmd = &cobra.Command{
	Use:   svcName,
	Short: "Consumes pr events from Hydro and updates alert link rows",
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

	es, err := app.NewES(ctx, cfg)
	if err != nil {
		return nil, cleanup.Clean, err
	}

	// Intentionally use a replica with the knowledge that we may miss some things due to replication lag
	// This is quite unlikely because we're just checking whether the alert links exist, and users don't usually
	// create a PR within seconds of creating the branch from the "Create branch/Update branch" experience
	// (since they would have chosen to create a PR in that case).
	db, closeDB, err := app.NewDBWithReplica(ctx, cfg)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	cleanup.Append(closeDB)

	als := alertlinks.NewService(alertlink.NewService(db), publisher, es)

	p := consumers.NewAlertLinkProcessor(als)

	// We want to start consuming from the newest offset instead of the beginning of the topic
	server, err := consumers.NewConsumerServer(*kc, cfg.KafkaGroup, p, logger, consumers.ConsumeFromNewestOffset)
	if err != nil {
		return nil, cleanup.Clean, err
	}

	return server, cleanup.Clean, nil
}
