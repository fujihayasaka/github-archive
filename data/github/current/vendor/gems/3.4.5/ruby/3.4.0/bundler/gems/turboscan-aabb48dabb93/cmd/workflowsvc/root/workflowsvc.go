// Package root is the entry point for command ingesting WorkflowExecution messages.
package root

import (
	"context"

	"github.com/github/turboscan/ts/appctx"
	"github.com/spf13/cobra"

	"github.com/github/turboscan/ts/app"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/hydro/consumers"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
)

const svcName = "workflowsvc"

var WorkflowSvcCmd = &cobra.Command{
	Use:   svcName,
	Short: "Workflowsvc is the entry point for ingesting WorkflowExecution messages.",
	Long: `Workflowsvc is the entry point for ingesting WorkflowExecution messages.
This will be used to track progress for the managed analysis.
`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return app.RunServiceFunc(svcName, serviceFunc)
	},
}

func serviceFunc(ctx context.Context, cfg *config.Config) (app.Server, app.CleanupFunc, error) {
	logger := appctx.Logger(ctx)
	statter := appctx.Stats(ctx)

	var cleaner app.Cleaner
	kc, err := cfg.NewKafkaConfig(logger, statter)
	if err != nil {
		return nil, cleaner.Clean, err
	}

	aqueduct, err := aqueduct.NewClient(cfg, logger, statter, nil)
	if err != nil {
		return nil, cleaner.Clean, err
	}

	ap := consumers.NewWorkflowEventProcessor(aqueduct)
	server, err := consumers.NewConsumerServer(*kc, cfg.KafkaGroup, ap, logger)
	if err != nil {
		return nil, cleaner.Clean, err
	}
	return server, cleaner.Clean, nil
}
