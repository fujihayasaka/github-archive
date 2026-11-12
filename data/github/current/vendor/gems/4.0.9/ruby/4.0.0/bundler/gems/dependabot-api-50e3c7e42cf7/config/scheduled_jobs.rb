# frozen_string_literal: true

require_relative "environment"
require "timer_daemon"
require "active_job/scheduled_job"

TIMERD_READINESS_PATH = "/tmp/timerd_started"
FileUtils.touch(TIMERD_READINESS_PATH)

ActiveJob::ScheduledJob.configure do |config|
  daemon = TimerDaemon.instance
  daemon.redis = Dependabot.redis
  daemon.err = Dependabot::Logger.method(:log)

  # report exceptions to Failbot
  daemon.error do |error, timer|
    Failbot.report(error, timer: timer.name)
  end

  config.error_reporter = lambda { |error, opts = {}|
    Failbot.report(error, opts)
  }

  config.timer_daemon = daemon
  config.scheduled_jobs = [
    ScheduledJobs::AuditEnqueuedUpdateJobs,
    ScheduledJobs::AuditPendingPullRequests,
    ScheduledJobs::DeleteAbandonedPendingPrs,
    ScheduledJobs::DeleteAbandonedPendingPrUpdates,
    ScheduledJobs::DeleteCreatedPendingPrs,
    ScheduledJobs::EnqueueRepoCiChecks,
    ScheduledJobs::EnqueueScheduledUpdateJobs,
    ScheduledJobs::MarkOldProcessingJobsAsTimedOut,
    ScheduledJobs::ReportUpdateJobBacklog,
    ScheduledJobs::TransitionInactiveSecurityUpdateReposToPaused,
  ]

  config.scheduled_jobs << ScheduledJobs::SynchronizeProxima if Dependabot.proxima?
end
