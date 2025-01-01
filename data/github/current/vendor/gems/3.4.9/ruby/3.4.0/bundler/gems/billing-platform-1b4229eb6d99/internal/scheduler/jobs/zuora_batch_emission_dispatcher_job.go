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

type ZuoraBatchEmissionDispatcherJob struct {
	ctx     context.Context
	cfg     *config.Config
	logger  log.Logger
	statter stats.Client
}

func NewZuoraBatchEmissionDispatcherJob(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	statter stats.Client,
) *ZuoraBatchEmissionDispatcherJob {
	return &ZuoraBatchEmissionDispatcherJob{
		ctx:     ctx,
		cfg:     cfg,
		logger:  logger.Named("ZuoraBatchEmissionDispatcherJob"),
		statter: statter,
	}
}

func (j *ZuoraBatchEmissionDispatcherJob) Run(zuoraPayload *models.ZuoraBatchEmissionPayload) error {
	// Initialize the messaging client
	client, err := messaging.NewMessagingClient(j.ctx, j.cfg, j.statter)
	if err != nil {
		j.logger.WithError(err).Error("error creating messaging client")
		return err
	}

	// Create a request using the zuora payload
	request, err := models.NewScheduleZuoraBatchEmissionRequest(zuoraPayload)
	if err != nil {
		j.logger.WithError(err).Error("error creating request from emission target")
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

	j.statter.Counter("published_zuora_batch_emission_dispatcher", stats.Tags{}, int64(1))

	return nil
}
