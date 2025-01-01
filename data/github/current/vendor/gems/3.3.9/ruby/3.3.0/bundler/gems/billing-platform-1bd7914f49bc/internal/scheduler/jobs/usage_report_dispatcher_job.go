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

type UsageReportDispatcherJob struct {
	ctx     context.Context
	cfg     *config.Config
	logger  log.Logger
	statter stats.Client
}

func NewUsageReportDispatcherJob(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	statter stats.Client,
) *UsageReportDispatcherJob {
	return &UsageReportDispatcherJob{
		ctx:     ctx,
		cfg:     cfg,
		logger:  logger.Named("UsageReportDispatcherJob"),
		statter: statter,
	}
}

func (j *UsageReportDispatcherJob) Run() error {
	client, err := messaging.NewMessagingClient(j.ctx, j.cfg, j.statter)
	if err != nil {
		j.logger.WithError(err).Error("error creating messaging client")
		return err
	}

	request, err := models.NewScheduleUsageReportJobsRequest()
	if err != nil {
		j.logger.WithError(err).Error("error creating request to trigger usage report jobs")
		return err
	}

	payload, err := json.Marshal(request)
	if err != nil {
		return errors.Wrap(err, "error serializing request")
	}

	job := aqueduct.Job{
		App:     j.cfg.AqueductApplication(),
		Queue:   messaging.GetQueueName(models.WorkerTypeRequestHandler, j.cfg.OverrideQueuePrefix),
		Payload: payload,
	}

	_, err = client.Send(j.ctx, job, messaging.MessageSenderOptions()...)
	if err != nil {
		return errors.Wrap(err, "error sending message to request-handler queue")
	}

	j.statter.Counter("published_usage_report_dispatcher_request", stats.Tags{}, int64(1))

	return nil
}
