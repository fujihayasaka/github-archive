// Package jobs contains all the jobs that the scheduler can run.
package jobs

import (
	"context"
	"encoding/json"

	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/aqueduct/queues"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/models"
)

// EmissionDispatcherJob is a job that dispatches emissions
type EmissionDispatcherJob struct {
	ctx     context.Context
	cfg     *config.Config
	logger  log.Logger
	statter stats.Client
	jobby   *jobs.Jobby
}

// NewEmissionDispatcherJob creates a new EmissionDispatcherJob
func NewEmissionDispatcherJob(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	statter stats.Client,
	jobby *jobs.Jobby,

) *EmissionDispatcherJob {
	return &EmissionDispatcherJob{
		ctx:     ctx,
		cfg:     cfg,
		logger:  logger,
		statter: statter,
		jobby:   jobby,
	}
}

// Run runs the job
func (j *EmissionDispatcherJob) Run(usageTime int64) error {
	payload, err := json.Marshal(models.ScheduleEmissionsJob{
		UsageTime: usageTime,
	})

	if err != nil {
		j.logger.WithError(err).Error("failed to marshal payload")
		return err
	}

	// Send job to Aqueduct
	_, err = j.jobby.Enqueue(j.ctx, jobs.JobNameScheduleEmissions, queues.QueueScheduleEmissions, payload)
	if err != nil {
		j.logger.WithError(err).Error("error sending message to licensify_schedule_emissions queue")
		return err
	}

	j.statter.Counter("emission_dispatcher.job.processed", stats.Tags{}, int64(1))

	return nil
}
