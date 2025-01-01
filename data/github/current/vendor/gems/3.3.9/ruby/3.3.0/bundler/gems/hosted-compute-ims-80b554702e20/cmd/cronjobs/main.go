package main

import (
	"context"
	"fmt"
	"os"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/config"
	"github.com/github/hosted-compute-ims/internal/cronjobs"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/resources"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/github/hosted-compute-ims/internal/vssf-clients/vssf_runner"
	"go.opentelemetry.io/otel/codes"
)

const (
	ReplicationJobName = "replication"
)

func main() {
	if err := realMain(); err != nil {
		panic(err)
	}
}

func realMain() error {
	ctx := context.Background()

	// load app config
	cfg := &config.Config{}
	if err := cfg.Load(); err != nil {
		return err
	}

	// initialize telemetry
	telem, err := telemetry.NewTelemetry(ctx, cfg.ServiceName, cfg.Telemetry)
	if err != nil {
		return err
	}
	defer telem.Shutdown(ctx)
	logger := telem.Logger

	err = featureflags.SetupNewGlobalFeatureFlagsClient(ctx, &cfg.FeatureFlags, logger)
	if err != nil {
		logger.ErrorWithReport("failed to initialize feature flags client", err)
		return err
	}

	// initialize  db stores
	imagesStore, err := store.NewImagesStoreWithMySQLConnection(&cfg.MySQL, logger, telem.Stats)
	if err != nil {
		logger.ErrorWithReport("failed to initialize database connection", err)
		return err
	}

	// initialize azure client
	azureClient, err := azure.NewAzureClient(&cfg.Azure, logger)
	if err != nil {
		logger.ErrorWithReport("failed to initialize azure client", err)
		return err
	}

	// initialize runner client
	runnerClient, err := vssf_runner.NewClient(&cfg.Runner, &cfg.Token, logger)
	if err != nil {
		logger.ErrorWithReport("failed to initialize runner client", err)
		return err
	}

	// initialize promotion client
	resourceManager := resources.NewManager(cfg.Resources, imagesStore, logger)

	// initialize job
	jobName, err := getJobName()
	if err != nil {
		logger.ErrorWithReport("failed to parse cron job name", err)
		return err
	}

	initializedJob, err := initializeJob(jobName, cronjobs.BaseJob{
		ImagesStore:  imagesStore,
		AzureClient:  azureClient,
		Manager:      resourceManager,
		RunnerClient: runnerClient,
		Logger:       logger,
	})
	if err != nil {
		logger.ErrorWithReport("failed to initialize cron job", err)
		return err
	}

	telem.Logger.Info("cron job started", kvp.String("job_name", jobName))
	telem.Stats.Counter("cronjob.started", stats.Tags{"job_name": jobName}, 1)
	spanCtx, span := telem.Tracer.Tracer.Start(ctx, fmt.Sprintf("CronJobs.%s", initializedJob.GetName()))
	defer span.End()

	err = initializedJob.Perform(spanCtx)
	if err != nil {
		logger.WithError(err).Error("cron job failed", kvp.String("job_name", jobName))
		span.SetStatus(codes.Error, err.Error())
	} else {
		logger.Info("cron job finished", kvp.String("job_name", jobName))
	}

	telem.Stats.Counter("cronjob.finished", stats.Tags{
		"job_name": jobName,
		"result":   fmt.Sprint(err == nil),
	}, 1)
	return nil
}

func initializeJob(jobName string, baseJob cronjobs.BaseJob) (cronjobs.Job, error) {
	switch jobName {
	case ReplicationJobName:
		return &cronjobs.ReplicationJob{BaseJob: baseJob}, nil
	default:
		return nil, fmt.Errorf("unknown cron job: %s", jobName)
	}
}

func getJobName() (string, error) {
	if len(os.Args) < 2 {
		return "", fmt.Errorf("failed to parse cron job name from arguments")
	}

	jobName := os.Args[1]
	if jobName == "" {
		return "", fmt.Errorf("failed to parse cron job name from arguments")
	}

	return jobName, nil
}
