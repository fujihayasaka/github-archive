// Package root provides the service that powers aqueductsvc
package root

import (
	"context"
	"time"

	"github.com/github/turboscan/ts/limits"
	"github.com/github/turboscan/ts/mysql/analysis"
	"github.com/github/turboscan/ts/mysql/archiver"
	"github.com/github/turboscan/ts/mysql/configuration"
	sfdb "github.com/github/turboscan/ts/mysql/suggestedfixes"
	"github.com/github/turboscan/ts/mysql/timeline"
	"github.com/github/turboscan/ts/sarif"

	"github.com/github/turboscan/ts/archivalstore"
	"github.com/github/turboscan/ts/mysql/analysismessage"
	"github.com/github/turboscan/ts/mysql/delivery"
	"github.com/github/turboscan/ts/mysql/rule"
	"github.com/github/turboscan/ts/mysql/tool"

	"github.com/github/turboscan/ts/enabled_status"

	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/github/turboscan/ts/processor"

	"github.com/github/turboscan/ts/appctx"
	"github.com/pkg/errors"

	"github.com/spf13/cobra"

	"github.com/github/turboscan/ts/app"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/delivery_processor"
	"github.com/github/turboscan/ts/hydro/publishers"
	"github.com/github/turboscan/ts/indexer"
	"github.com/github/turboscan/ts/jobs"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
)

const (
	svcName          = "aqueductsvc"
	shortDescription = "is responsible for executing Aqueduct workers"
	longDescription  = `aqueductsvc is responsible for executing Aqueduct workers.

To manually send a job to be processed do:

  export AQUEDUCT_ADDR=http://localhost:18081
  PAYLOAD=$(echo '{"Message": "potato"}' | base64)
  curl --header "Content-Type:application/json" \
     --data '{"app": "turboscan-dev", "queue":"turboscan-echo", "payload":"'$PAYLOAD'"}' \
    $AQUEDUCT_ADDR/twirp/aqueduct.api.v1.JobQueueService/Send

This will encode a job with a payload "potato" on the turboscan-echo queue.
The turboscan-echo queue is a special queue for testing, the other queue we use is "default".
More queues can be added to define various priorities and processing strategies.`
)

var AqueductCmd = &cobra.Command{
	Use:   svcName,
	Short: shortDescription,
	Long:  longDescription,
	RunE: func(cmd *cobra.Command, args []string) error {
		return app.RunServiceFunc(svcName, serviceFunc(cmd))
	},
}

type WorkerType string

const (
	WorkerTypeDefault             WorkerType = "default"
	WorkerTypeAutofixHighPriority WorkerType = "autofix-high-priority"
	WorkerTypeAutofixLowPriority  WorkerType = "autofix-low-priority"
)

// String is used both by fmt.Print and by Cobra in help text
func (e *WorkerType) String() string {
	return string(*e)
}

// Set must have pointer receiver so it doesn't change the value of a copy
func (e *WorkerType) Set(v string) error {
	switch v {
	case "default", "autofix-high-priority", "autofix-low-priority":
		*e = WorkerType(v)
		return nil
	default:
		return errors.New(`must be one of "default", "autofix-high-priority", or "autofix-low-priority"`)
	}
}

// Type is only used in help text
func (e *WorkerType) Type() string {
	return "WorkerType"
}

func serviceFunc(cmd *cobra.Command) func(ctx context.Context, cfg *config.Config) (app.Server, app.CleanupFunc, error) {
	return func(ctx context.Context, cfg *config.Config) (app.Server, app.CleanupFunc, error) {
		logger, statter := appctx.Logger(ctx), appctx.Stats(ctx)

		var cleanup app.Cleaner

		errorHandler := func(_ hydro.Message, err error) {
			appctx.Report(ctx, err, nil)
		}

		kc, err := cfg.NewKafkaConfig(logger, statter)
		if err != nil {
			return nil, cleanup.Clean, err
		}

		batchPublisher, err := publishers.New(*kc, statter, hydro.WithBatchSize(250), hydro.WithBatchBytes(10*1024*1024), hydro.WithBatchTimeout(5*time.Second), hydro.WithAsync(true), hydro.WithWriteErrorHandler(errorHandler))
		if err != nil {
			return nil, cleanup.Clean, err
		}
		cleanup.Append(batchPublisher.Close)

		publisher, err := publishers.New(*kc, statter)
		if err != nil {
			return nil, cleanup.Clean, err
		}
		cleanup.Append(publisher.Close)

		jobs, err := aqueduct.NewClient(cfg, logger, statter, nil)
		if err != nil {
			return nil, cleanup.Clean, err
		}

		sarifStore, closeSarifStore, err := app.NewSarifStore(ctx, cfg)
		if err != nil {
			return nil, cleanup.Clean, err
		}
		cleanup.Append(closeSarifStore)

		db, closeDB, err := app.NewDB(ctx, cfg)
		if err != nil {
			return nil, cleanup.Clean, err
		}
		cleanup.Append(closeDB)

		alertService, err := app.NewAlertService(db)
		if err != nil {
			return nil, cleanup.Clean, err
		}

		repoService := repository.NewService(db)
		maDataService := managedanalysis.NewService(db, publisher)

		enabledStatusService := enabled_status.NewEnabledStatusService(db, alertService, repoService, maDataService, publisher, true)

		repoAPI, err := cfg.NewRepositoryAPI(logger, statter)
		if err != nil {
			return nil, cleanup.Clean, err
		}

		maService, err := app.NewManagedAnalysisService(ctx, cfg, repoAPI, repoService, enabledStatusService, maDataService, publisher)
		if err != nil {
			return nil, cleanup.Clean, err
		}

		archivalStore, err := archivalstore.NewArchivalStoreFromConfig(sarifStore, cfg)
		if err != nil {
			return nil, cleanup.Clean, err
		}

		archiveService := archiver.NewService(db, archivalStore)

		limitsSelector := limits.NewLimitSelector(cfg.Limits(), cfg.DisableSarifHardLimit)

		ruleMetadataAugmentor, err := sarif.DefaultRuleMetadataAugmentor()
		if err != nil {
			return nil, cleanup.Clean, err
		}

		deliveryService := delivery.NewService(db)

		processor := processor.New(
			alertService,
			analysis.NewService(db),
			deliveryService,
			analysismessage.NewService(db),
			sarifStore,
			archivalStore,
			tool.NewService(db, limitsSelector),
			configuration.NewService(db),
			rule.NewService(db),
			timeline.NewService(db),
			repoService,
			repoAPI,
			limitsSelector,
			ruleMetadataAugmentor,
			maDataService,
			publishers.NewHydroAlertHandler(batchPublisher),
			jobs,
		)

		client, err := aqueduct.NewClient(cfg, logger, statter, nil)
		if err != nil {
			return nil, cleanup.Clean, err
		}

		workerType := WorkerType(cmd.Flag("worker-type").Value.String())

		// Note that there is also an insightsPublisher inside the processor, we use both
		// as long as we both allow sync and async publishing. After we move to async only
		// we can remove the insightsPublisher from the processor.
		insightsPublisher, err := publishers.New(*kc, statter)
		if err != nil {
			return nil, cleanup.Clean, err
		}
		cleanup.Append(insightsPublisher.Close)
		insightsHandler := publishers.NewInsightsHydroAlertHandler(insightsPublisher, alertService)

		es, err := app.NewES(ctx, cfg)
		if err != nil {
			return nil, cleanup.Clean, err
		}

		sfDataService := sfdb.NewService(db)

		sfService, err := app.NewSuggestedFixesService(ctx, cfg, sfDataService, alertService, archiveService, limitsSelector, publisher, client)
		if err != nil {
			return nil, cleanup.Clean, err
		}

		s := &aqueduct.TSServices{
			ManagedAnalyses:              maService,
			SuggestedFixes:               sfService,
			GetDeliveriesByWorkflowRunID: deliveryService.GetDeliveriesByWorkflowRunID,
			DeliveryProcessor:            delivery_processor.NewDeliveryProcessor(deliveryService, processor, publisher, enabledStatusService, 2*time.Minute),
			Aqueduct:                     client,
			Indexer:                      indexer.NewService(alertService, repoService, repoAPI, es, insightsHandler),
			IsEnterpriseEnv:              cfg.IsEnterpriseEnv(),
		}

		worker, err := aqueduct.NewWorker(ctx, s, client, cfg.Environment, workerType.String(), aqueduct.EnabledQueues(cfg.AqueductQueues, GetRegistry(workerType), logger))
		if err != nil {
			return nil, cleanup.Clean, err
		}
		return worker, cleanup.Clean, nil
	}
}

// GetRegistry returns the registry of jobs we care about.
// If you add a job, extend this method
func GetRegistry(workerType WorkerType) aqueduct.Registry {
	r := aqueduct.Registry{}
	switch workerType {
	case WorkerTypeAutofixHighPriority:
		aqueduct.RegisterJob[jobs.SuggestedFixAlertGenerateHighPriorityJob](r)
	case WorkerTypeAutofixLowPriority:
		aqueduct.RegisterJob[jobs.SuggestedFixAlertGenerateLowPriorityJob](r)
	case WorkerTypeDefault:
		aqueduct.RegisterJob[jobs.SuggestedFixTelemetry](r)
		aqueduct.RegisterJob[aqueduct.EchoJob](r)
		aqueduct.RegisterJob[jobs.SetDynamicRunConclusion](r)
		aqueduct.RegisterJob[jobs.RunCodeqlOnPush](r)
		aqueduct.RegisterJob[jobs.RunCodeqlOnPullRequest](r)
		aqueduct.RegisterJob[jobs.SkipDependabot](r)
		aqueduct.RegisterJob[jobs.PublishWorkflowRunAnnotations](r)
		aqueduct.RegisterJob[jobs.ProcessDelivery](r)
		aqueduct.RegisterJob[jobs.AlertIndexing](r)
		aqueduct.RegisterJob[jobs.GenerateDependabotFixJob](r)
	}
	return r
}

func init() {
	var workerType = WorkerTypeDefault
	AqueductCmd.Flags().Var(&workerType, "worker-type", "Defines what jobs this worker will process. Allowed: default, autofix-high-priority, autofix-low-priority")
}
