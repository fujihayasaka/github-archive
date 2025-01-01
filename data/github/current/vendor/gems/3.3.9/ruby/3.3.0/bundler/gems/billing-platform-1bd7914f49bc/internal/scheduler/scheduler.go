package scheduler

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/github/billing-platform/internal/cosmoslocker"
	"github.com/github/billing-platform/internal/featureflag"
	"github.com/github/billing-platform/internal/scheduler/jobs"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/pkg/errors"

	"github.com/github/github-telemetry-go/log"
	exceptions "github.com/github/go-exceptions"
	stats "github.com/github/go-stats"
	"github.com/go-co-op/gocron"
)

// Scheduler is responsible for scheduling and updating messages
type Scheduler struct {
	cronScheduler *gocron.Scheduler
	context       context.Context
	db            interfaces.Database
	cfg           *config.Config
	logger        log.Logger
	reporter      *exceptions.Reporter
	statter       stats.Client
	flagger       featureflag.FlagChecker
}

func NewScheduler(
	ctx context.Context,
	db interfaces.Database,
	cfg *config.Config,
	logger log.Logger,
	reporter *exceptions.Reporter,
	statter stats.Client,
	flagger featureflag.FlagChecker,
) *Scheduler {
	return &Scheduler{
		cronScheduler: gocron.NewScheduler(models.UTCNow().Location()),
		context:       ctx,
		db:            db,
		cfg:           cfg,
		logger:        logger,
		reporter:      reporter,
		statter:       statter,
		flagger:       flagger,
	}
}

// Run starts the scheduler and blocks. Each cron job spawns off an anonymous function.
func (s *Scheduler) Run() error {
	locker := cosmoslocker.NewCosmosLocker(s.db, s.logger, 30*time.Minute, s.flagger)
	s.cronScheduler.WithDistributedLocker(locker)
	startOfHour := time.Now().Truncate(time.Hour).Add(time.Hour)

	// Emission dispatcher job
	if _, err := s.cronScheduler.Every(1).Day().At("5:00").Name("EmissionDispatcherJob").Do(func() {
		s.statter.Counter("cron_job.start", stats.Tags{"job": "EmissionDispatcherJob"}, 1)

		// Tell the dispatcher to query line items from the previous day
		now := time.Now().UTC()
		then := now.AddDate(0, 0, -1)
		usageDate := &models.UsageDate{
			Year:  int64(then.Year()),
			Month: int64(then.Month()),
			Day:   int64(then.Day()),
		}

		err := jobs.NewEmissionDispatcherJob(s.context, s.cfg, s.logger, s.statter).Run(usageDate)
		if err != nil {
			s.reportError("EmissionDispatcherJob", err)
		}
		s.statter.Counter("cron_job.end", stats.Tags{"job": "EmissionDispatcherJob", "success": strconv.FormatBool(err == nil)}, 1)
	}); err != nil {
		return errors.Wrap(err, "error scheduling EmissionDispatcherJob")
	}

	// Azure emission dispatcher job
	if _, err := s.cronScheduler.Every(1).Day().At("8:00").Name("AzureEmissionDispatcherJob").Do(func() {
		s.statter.Counter("cron_job.start", stats.Tags{"job": "AzureEmissionDispatcherJob"}, 1)

		// Tell the dispatcher to query line items from the previous day
		now := time.Now().UTC()
		then := now.AddDate(0, 0, -1)
		usageDate := &models.AzureUsageDate{
			Year:  int64(then.Year()),
			Month: int64(then.Month()),
			Day:   int64(then.Day()),
		}

		err := jobs.NewAzureEmissionDispatcherJob(s.context, s.cfg, s.logger, s.statter).Run(usageDate)
		if err != nil {
			s.reportError("AzureEmissionDispatcherJob", err)
		}
		s.statter.Counter("cron_job.end", stats.Tags{"job": "AzureEmissionDispatcherJob", "success": strconv.FormatBool(err == nil)}, 1)
	}); err != nil {
		return errors.Wrap(err, "error scheduling AzureEmissionDispatcherJob")
	}

	// Monthly Invoice Generation job
	if _, err := s.cronScheduler.Every(1).Day().At("1:00").Name("InvoiceGenerationJob").Do(func() {
		s.statter.Counter("cron_job.start", stats.Tags{"job": "InvoiceGenerationJob"}, 1)
		timeNow := time.Now()
		oneMonthAgo := timeNow.AddDate(0, -1, 0)

		// Do nothing if oneMonthAgo is the same as the current month.
		// This can happen when we transition from a month with shorter days to one with longer days.
		//   For example, 2024-03-30 - 1 month = 2024-03-01
		//
		// In those cases we would end up generating invoices early which can be problematic when we
		// expect to upload usage to Zuora only at the end of every month.
		if timeNow.Month() == oneMonthAgo.Month() {
			s.statter.Counter("cron_job.end", stats.Tags{"job": "InvoiceGenerationJob", "skipped": "true"}, 1)
			return
		}

		ipd := &models.InvoicePartitionDetail{
			Period: models.InvoiceMonthly,
			Year:   int64(oneMonthAgo.Year()),
			Month:  int64(oneMonthAgo.Month()),
		}
		err := jobs.NewInvoiceGenerationJob(s.context, s.cfg, s.logger, s.statter).Run(ipd)
		if err != nil {
			s.reportError("InvoiceGenerationJob", err)
		}
		s.statter.Counter("cron_job.end", stats.Tags{"job": "InvoiceGenerationJob", "success": strconv.FormatBool(err == nil)}, 1)
	}); err != nil {
		return errors.Wrap(err, "error scheduling InvoiceGenerationJob")
	}

	// Watermark dispatcher job
	if _, err := s.cronScheduler.Every(1).Hour().StartAt(startOfHour).Name("WatermarkJob").Do(func() {
		timeNow := models.UTCNow()
		jobRun := &models.WatermarkJobRun{
			Year:  int64(timeNow.Year()),
			Month: int64(timeNow.Month()),
			Day:   int64(timeNow.Day()),
			Hour:  int64(timeNow.Hour()),
		}
		s.statter.Counter("cron_job.start", stats.Tags{"job": "WatermarkJob"}, 1)
		err := jobs.NewWatermarkDispatcherJob(s.context, s.cfg, s.logger, s.statter).Run(jobRun)
		if err != nil {
			s.reportError("WatermarkJob", err)
		}
		s.statter.Counter("cron_job.end", stats.Tags{"job": "WatermarkJob", "success": strconv.FormatBool(err == nil)}, 1)
	}); err != nil {
		return errors.Wrap(err, "error scheduling WatermarkJob")
	}

	// High watermark dispatcher
	if _, err := s.cronScheduler.Every(1).Month(1).At("00:05").Name("HighWatermarkRolloverJob").Do(func() {
		s.statter.Counter("cron_job.start", stats.Tags{"job": "HighWatermarkRolloverJob"}, 1)
		timeNow := time.Now()
		jobRun := &models.HighWatermarkRolloverJobRun{
			Year:   int64(timeNow.Year()),
			Month:  int64(timeNow.Month()),
			DryRun: false,
		}
		err := jobs.NewHighWatermarkRolloverJob(s.context, s.cfg, s.logger, s.statter).Run(jobRun)
		if err != nil {
			s.reportError("HighWatermarkRolloverJob", err)
		}
		s.statter.Counter("cron_job.end", stats.Tags{"job": "HighWatermarkRolloverJob", "success": strconv.FormatBool(err == nil)}, 1)
	}); err != nil {
		return errors.Wrap(err, "error scheduling HighWatermarkRolloverJob")
	}

	// Schedule the UsageReportDispatcherJob to run every 1 minute
	if _, err := s.cronScheduler.Every(1).Minute().StartAt(time.Now().Round(time.Minute)).Name("UsageReportDispatcherJob").Do(func() {
		s.statter.Counter("cron_job.start", stats.Tags{"job": "UsageReportDispatcherJob"}, 1)
		err := jobs.NewUsageReportDispatcherJob(s.context, s.cfg, s.logger, s.statter).Run()
		if err != nil {
			s.reportError("UsageReportDispatcherJob", err)
		}
		s.statter.Counter("cron_job.end", stats.Tags{"job": "UsageReportDispatcherJob", "success": strconv.FormatBool(err == nil)}, 1)
	}); err != nil {
		return errors.Wrap(err, "error scheduling UsageReportDispatcherJob")
	}

	s.cronScheduler.StartAsync()

	return nil
}

func (s *Scheduler) Stop() {
	s.cronScheduler.Stop()
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

func (s *Scheduler) RunAsync() {
	go func() {
		if err := s.Run(); err != nil {
			s.reportError("gocron job initialization", err)
		}
	}()

	<-s.context.Done()
}
