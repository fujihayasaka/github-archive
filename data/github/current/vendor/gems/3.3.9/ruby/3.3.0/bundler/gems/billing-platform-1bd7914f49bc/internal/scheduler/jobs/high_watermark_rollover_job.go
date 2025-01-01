package jobs

import (
	"context"
	"encoding/json"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/messaging"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"
)

type HighWatermarkRolloverJob struct {
	ctx     context.Context
	cfg     *config.Config
	logger  log.Logger
	statter stats.Client
}

func NewHighWatermarkRolloverJob(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	statter stats.Client,
) *HighWatermarkRolloverJob {
	return &HighWatermarkRolloverJob{
		ctx:     ctx,
		cfg:     cfg,
		logger:  logger.Named("HighWatermarkRolloverJob"),
		statter: statter,
	}
}

func (j *HighWatermarkRolloverJob) Run(jobRun *models.HighWatermarkRolloverJobRun) error {
	// Initialize the messaging client
	client, err := messaging.NewMessagingClient(j.ctx, j.cfg, j.statter)
	if err != nil {
		return err
	}

	// Create a request
	request, err := models.NewScheduleHighWatermarkRolloverJobRequest(jobRun)
	if err != nil {
		return err
	}

	// Convert the request to JSON
	payload, err := json.Marshal(request)
	if err != nil {
		return errors.Wrap(err, "error serializing request")
	}

	// Create job
	job := aqueduct.Job{
		App:     j.cfg.AqueductApplication(),
		Queue:   messaging.GetQueueName(models.WorkerTypeRequestHandler, j.cfg.OverrideQueuePrefix),
		Payload: payload,
	}

	// Send job to Aqueduct
	_, err = client.Send(j.ctx, job, messaging.MessageSenderOptions()...)
	if err != nil {
		return errors.Wrap(err, "error sending message to request-handler queue")
	}

	j.statter.Counter("high_watermark_rollover_job", stats.Tags{}, int64(1))

	return nil
}
