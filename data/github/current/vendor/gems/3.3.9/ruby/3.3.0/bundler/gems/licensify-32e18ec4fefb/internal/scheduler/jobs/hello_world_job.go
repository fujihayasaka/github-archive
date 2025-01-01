// Package jobs is used for scheduled jobs
package jobs

import (
	"context"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	stats "github.com/github/go-stats"
	"github.com/github/licensify/internal/config"
)

// HelloWorldJob is used to test the scheduler
type HelloWorldJob struct {
	ctx     context.Context
	cfg     *config.Config
	logger  log.Logger
	statter stats.Client
}

// HelloWorldJobRun is used to test the scheduler
type HelloWorldJobRun struct {
	Year  int64
	Month int64
	Day   int64
	Hour  int64
}

// NewHelloWorldJob is used to test the scheduler
func NewHelloWorldJob(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	statter stats.Client,
) *HelloWorldJob {
	return &HelloWorldJob{
		ctx:     ctx,
		cfg:     cfg,
		logger:  logger.Named("HelloWorldJob"),
		statter: statter,
	}
}

// Run is used to test the scheduler
func (j *HelloWorldJob) Run(jobRun *HelloWorldJobRun) error {
	telem, _ := telemetry.NewFromEnv()
	logger := j.cfg.ConfigureLogger(telem.Logger, "Scheduler")
	logger.Info("Hello World!")

	return nil
}
