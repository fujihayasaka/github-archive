package main

import (
	"context"
	"fmt"
	"os"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/config"
	"github.com/github/hosted-compute-ims/internal/cronjobs"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/promotion"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/github/hosted-compute-ims/internal/telemetry"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"
	"github.com/github/hosted-compute-ims/internal/telemetry/statter"
	"github.com/github/hosted-compute-ims/internal/telemetry/tracer"
	"github.com/github/hosted-compute-ims/internal/vssf-clients/vssf_runner"
	"github.com/google/uuid"
	"go.opentelemetry.io/otel/codes"
)

const (
	CuratedImageReplicationJobName  = "curated-image-replication"
	CustomerImageReplicationJobName = "customer-image-replication"
	CuratedImageRetentionJobName    = "curated-image-retention"
	CustomerImageRetentionJobName   = "customer-image-retention"
	TelemetryJobName                = "telemetry"
	ImageEventsPublishingJobName    = "customer-image-events-publishing"
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

	telem, err := telemetry.InitializeTelemetry(ctx, &cfg.Telemetry)
	if err != nil {
		return fmt.Errorf("failed to initialize telemetry: %w", err)
	}
	defer telem.Shutdown(ctx)

	// Get the job name for use in logger
	jobName, err := getJobName()
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to parse cron job name", err)
		return err
	}

	jobId := uuid.NewString()

	ctx = stash.WithLoggingFields(ctx,
		kvp.String("cron_job_name", jobName),
		kvp.String("cron_job_id", jobId),
	)
	ctx = stash.WithStatterFields(ctx,
		kvp.String("cron_job_name", jobName),
	)

	err = featureflags.SetupNewGlobalFeatureFlagsClient(ctx, &cfg.FeatureFlags)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to initialize feature flags client", err)
		return err
	}

	// initialize  db stores
	imagesStore, err := store.NewImagesStoreWithMySQLConnection(&cfg.MySQL)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to initialize database connection", err)
		return err
	}

	// initialize runner client
	runnerClient, err := vssf_runner.NewClient(&cfg.Runner, &cfg.Token)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to initialize runner client", err)
		return err
	}

	// initialize promotion client
	promotionClient, err := promotion.NewImagePromotionClient(ctx, &cfg.Worker.Aqueduct, &cfg.Azure, &cfg.MCP, &cfg.TwirpServer.JWTConfig, imagesStore)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to initialize promotion client", err)
		return err
	}

	// initialize job
	initializedJob, err := initializeJob(jobName, cronjobs.BaseJob{
		ImagesStore:     imagesStore,
		PromotionClient: promotionClient,
		RunnerClient:    runnerClient,
	})
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to initialize cron job", err)
		return err
	}

	logger.Info(ctx, "cron job started")
	statter.Increment(ctx, "cronjob.started")
	spanCtx, span := tracer.StartSpan(ctx, fmt.Sprintf("CronJobs.%s", initializedJob.GetName()))
	defer span.End()

	err = initializedJob.Perform(spanCtx)
	if err != nil {
		logger.WithError(err).Error(ctx, "cron job failed")
		span.SetStatus(codes.Error, err.Error())
	} else {
		logger.Info(ctx, "cron job finished")
	}

	statter.Increment(ctx, "cronjob.finished", kvp.Bool("result", err == nil))
	return nil
}

func initializeJob(jobName string, baseJob cronjobs.BaseJob) (cronjobs.Job, error) {
	switch jobName {
	case CuratedImageReplicationJobName:
		return &cronjobs.ReplicationJob{BaseJob: baseJob, Kind: models.ImageType_Curated}, nil
	case CustomerImageReplicationJobName:
		return &cronjobs.ReplicationJob{BaseJob: baseJob, Kind: models.ImageType_Customer}, nil
	case CuratedImageRetentionJobName:
		return &cronjobs.RetentionJob{BaseJob: baseJob, Kind: models.ImageType_Curated}, nil
	case CustomerImageRetentionJobName:
		return &cronjobs.RetentionJob{BaseJob: baseJob, Kind: models.ImageType_Customer}, nil
	case TelemetryJobName:
		return &cronjobs.TelemetryJob{BaseJob: baseJob}, nil
	case ImageEventsPublishingJobName:
		return &cronjobs.ImageEventsPublishingJob{BaseJob: baseJob}, nil
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
