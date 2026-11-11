# frozen_string_literal: true

# Run in production every minute
#
# Report queue depth to metrics infra
module ScheduledJobs
  class ReportUpdateJobBacklog < ApplicationScheduledJob
    queue_as :default
    default_retries_for_idempotent_jobs

    schedule interval: 1.minute

    def perform
      MetricsClient.gauge(
        "app_update_job_backlog",
        ActiveRecord::Base.connected_to(role: :reading) do
          UpdateJobTransition.where(most_recent: true, to_state: :enqueued).count
        end,
      )
    end
  end
end
