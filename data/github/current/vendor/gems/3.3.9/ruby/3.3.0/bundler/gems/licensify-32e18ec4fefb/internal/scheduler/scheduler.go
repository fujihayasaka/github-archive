// Package scheduler is for scheduled jobs
package scheduler

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/log"
	exceptions "github.com/github/go-exceptions"
	stats "github.com/github/go-stats"
	"github.com/github/licensify/internal/aqueduct"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/cosmos"
	"github.com/github/licensify/internal/cosmoslocker"
	schedulerJobs "github.com/github/licensify/internal/scheduler/jobs"
	"github.com/go-co-op/gocron/v2"
)

// Scheduler is responsible for scheduling and updating messages
type Scheduler struct {
	cronScheduler gocron.Scheduler
	context       context.Context
	readWriter    cosmos.ReadWriter
	cfg           *config.Config
	logger        log.Logger
	reporter      *exceptions.Reporter
	statter       stats.Client
}

// NewScheduler creates a new Scheduler
func NewScheduler(
	ctx context.Context,
	readWriter cosmos.ReadWriter,
	cfg *config.Config,
	logger log.Logger,
	reporter *exceptions.Reporter,
	statter stats.Client,
) *Scheduler {
	locker := cosmoslocker.NewCosmosLocker(statter, logger, readWriter)
	scheduler, err := gocron.NewScheduler(gocron.WithDistributedLocker(locker))

	if err != nil {
		return nil
	}

	return &Scheduler{
		cronScheduler: scheduler,
		context:       ctx,
		readWriter:    readWriter,
		cfg:           cfg,
		logger:        logger,
		reporter:      reporter,
		statter:       statter,
	}
}

// Run starts the scheduler and blocks. Each cron job spawns off an anonymous function.
func (s *Scheduler) Run() error {
	// Hello World job
	if _, err := s.cronScheduler.NewJob(
		gocron.CronJob("0 * * * *", false),
		gocron.NewTask(
			func() {
				timeNow := time.Now().UTC()
				jobRun := &schedulerJobs.HelloWorldJobRun{
					Year:  int64(timeNow.Year()),
					Month: int64(timeNow.Month()),
					Day:   int64(timeNow.Day()),
					Hour:  int64(timeNow.Hour()),
				}
				s.statter.Counter("cron_job.start", stats.Tags{"job": "HelloWorldJob"}, 1)
				err := schedulerJobs.NewHelloWorldJob(s.context, s.cfg, s.logger, s.statter).Run(jobRun)
				if err != nil {
					s.reportError("HelloWorldJob", err)
				}
				s.statter.Counter("cron_job.end", stats.Tags{"job": "HelloWorldJob", "success": strconv.FormatBool(err == nil)}, 1)
			},
		),
		gocron.WithName("HelloWorldJob"),
	); err != nil {
		return err
	}

	// Emissions dispatcher job
	if _, err := s.cronScheduler.NewJob(
		// Run daily at 6:30 PM UTC / 11:30 AM PDT / 10:30 AM PST
		gocron.CronJob("30 18 * * *", false),
		gocron.NewTask(
			func() {
				aqueductClient, err := aqueduct.NewClient(
					s.cfg.AqueductURL,
					s.cfg.AqueductAPIKey,
					s.cfg.AqueductAPIKeyVersion,
					s.statter,
				)
				if err != nil {
					s.reportError("EmissionDispatcherJob", err)
					return
				}
				jobby := &jobs.Jobby{Cfg: s.cfg, AqueductClient: aqueductClient}

				timeNow := time.Now().UTC()
				s.statter.Counter("cron_job.start", stats.Tags{"job": "EmissionDispatcherJob"}, 1)
				err = schedulerJobs.NewEmissionDispatcherJob(s.context, s.cfg, s.logger, s.statter, jobby).Run(timeNow.Unix())
				if err != nil {
					s.reportError("EmissionDispatcherJob", err)
				}
				s.statter.Counter("cron_job.end", stats.Tags{"job": "EmissionDispatcherJob", "success": strconv.FormatBool(err == nil)}, 1)
			},
		),
		gocron.WithName("EmissionDispatcherJob"),
	); err != nil {
		return err
	}

	s.cronScheduler.Start()

	return nil
}

// Stop the scheduler
func (s *Scheduler) Stop() {
	if err := s.cronScheduler.Shutdown(); err != nil {
		s.reportError("gocron job shutdown", err)
	}
}

// Helper function that logs an error and tries to report it to Sentry.
// If Sentry reporting fails, it logs that error as well (will have to check Splunk for it.)
func (s *Scheduler) reportError(jobName string, err error) {
	s.logger.WithError(err).Error(fmt.Sprintf("%s failed", jobName))
	s.statter.Counter("cron_job.error", stats.Tags{"job": jobName}, 1)
	if e := s.reporter.Report(s.context, err, nil); e != nil {
		s.logger.WithError(err).Error("error occurred when reporting error to Sentry")
	}
}

// RunAsync is used to start the scheduler
func (s *Scheduler) RunAsync() {
	go func() {
		if err := s.Run(); err != nil {
			s.reportError("gocron job initialization", err)
		}
	}()

	<-s.context.Done()
}
