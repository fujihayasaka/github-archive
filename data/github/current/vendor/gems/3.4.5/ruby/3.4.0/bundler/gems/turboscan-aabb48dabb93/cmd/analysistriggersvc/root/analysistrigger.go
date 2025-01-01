// Package root provides the service that powers analysistriggersvc
package root

import (
	"context"
	"time"

	"github.com/spf13/cobra"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/mysql/managedanalysis"

	"github.com/github/turboscan/ts/app"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/hydro/consumers"
	"github.com/github/turboscan/ts/hydro/publishers"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"golang.org/x/sync/errgroup"
)

const svcName = "analysistriggersvc"

var AnalysisTriggerCmd = &cobra.Command{
	Use:   svcName,
	Short: "Consumes push and pr events from the Hydro and runs managed analysis jobs for the affected repositories",
	Long:  "Consumes push and pr events from the Hydro and runs managed analysis jobs for the affected repositories.",
	RunE: func(cmd *cobra.Command, args []string) error {
		return app.RunServiceFunc(svcName, serviceFunc)
	},
}

const POLLING_INTERVAL = 60 * time.Second

type AnalysisTriggerConsumer struct {
	processor *consumers.AnalysisTriggerProcessor
	consumer  *consumers.ConsumerServer
}

func (s *AnalysisTriggerConsumer) Start(ctx context.Context) error {
	err := s.processor.Init(ctx)
	if err != nil {
		return err
	}
	g, gCtx := errgroup.WithContext(ctx)
	g.Go(func() error { return s.processor.PollEnabledRepos(gCtx, POLLING_INTERVAL) })
	g.Go(func() error { return s.consumer.Start(gCtx) })
	return g.Wait()
}

func (s *AnalysisTriggerConsumer) Stop(ctx context.Context) error {
	return s.consumer.Stop(ctx)
}

func serviceFunc(ctx context.Context, cfg *config.Config) (app.Server, app.CleanupFunc, error) {
	logger, statter := appctx.Logger(ctx), appctx.Stats(ctx)

	kc, err := cfg.NewKafkaConfig(logger, statter)
	var cleanup app.Cleaner
	if err != nil {
		return nil, cleanup.Clean, err
	}

	aqueductClient, err := aqueduct.NewClient(cfg, logger, statter, nil)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	hydroPublisher, err := publishers.New(*kc, statter)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	cleanup.Append(hydroPublisher.Close)

	maClient, err := cfg.NewManagedAnalysesAPI(logger, statter)
	if err != nil {
		return nil, cleanup.Clean, err
	}

	db, closeDB, err := app.NewDB(ctx, cfg)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	cleanup.Append(closeDB)

	p := consumers.NewAnalysisTriggerProcessor(hydroPublisher, managedanalysis.NewService(db, hydroPublisher), aqueductClient, maClient, !cfg.IsEnterpriseEnv())

	// We want to start consuming from the newest offset instead of the beginning of the topic
	consumer, err := consumers.NewConsumerServer(*kc, cfg.KafkaGroup, p, logger, consumers.ConsumeFromNewestOffset)
	if err != nil {
		return nil, cleanup.Clean, err
	}

	return &AnalysisTriggerConsumer{processor: p, consumer: consumer}, cleanup.Clean, nil
}
