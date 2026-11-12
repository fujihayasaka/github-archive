# frozen_string_literal: true

# This job looks for jobs that are still in the 'processing' state after their
# 'expired_at' timestamp has been exceeded and transitions them to 'timed_out'.
#
# For certain package managers, this will also increase the instance size
# of the job's associated UpdateConfig, assuming the issue is due to
# the job running out of memory.
module ScheduledJobs
  class MarkOldProcessingJobsAsTimedOut < ApplicationScheduledJob
    queue_as :default
    default_retries_for_idempotent_jobs

    schedule interval: 15.minutes

    def perform(limit: 1000)
      old_processing_update_jobs.limit(limit).find_each do |job|
        HandleUpdaterTimeout.new(
          update_job: job,
          event_source: "job.mark_old_processing_jobs_as_timed_out"
        ).run
      end

      MetricsClient.gauge(
        "scheduled_jobs.mark_old_processing_jobs_as_timed_out.backlog",
        ActiveRecord::Base.connected_to(role: :reading) do
          old_processing_update_jobs.count
        end,
      )
    end

    private

    def old_processing_update_jobs
      UpdateJob.in_state(:processing).expired
    end
  end
end
