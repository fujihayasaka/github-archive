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

type ZeroOutQuantitiesJob struct {
	ctx     context.Context
	cfg     *config.Config
	logger  log.Logger
	statter stats.Client
}

func NewZeroOutQuantitiesJob(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	statter stats.Client,
) *ZeroOutQuantitiesJob {
	return &ZeroOutQuantitiesJob{
		ctx:     ctx,
		cfg:     cfg,
		logger:  logger.Named("ZeroOutQuantitiesJob"),
		statter: statter,
	}
}

func (j *ZeroOutQuantitiesJob) Run(jobRun *models.ZeroOutQuantitiesJobRun) error {
	// Initialize the messaging client
	client, err := messaging.NewMessagingClient(j.ctx, j.cfg, j.statter)
	if err != nil {
		j.logger.WithError(err).Error("error creating messaging client")
		return err
	}

	// Create a request using the watermark job run
	request, err := models.NewScheduleZeroOutQuantitiesJobsRequest(jobRun)
	if err != nil {
		j.logger.WithError(err).Error("error creating request from zero-out-quantities job run")
		return err
	}

	// Convert the request to JSON
	payload, err := json.Marshal(request)
	if err != nil {
		j.logger.WithError(err).Error("error serializing request")
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
		j.logger.WithError(err).Error("error sending message to request-handler queue")
		return errors.Wrap(err, "error sending message to request-handler queue")
	}

	return nil
}
