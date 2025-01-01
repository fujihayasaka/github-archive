# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Actions
  class ExportGhesActionsJobExecutionsJob < ApplicationJob
    queue_as :github_connect

    # This job is only ran in GHES and only if the Server Statisitic feature is enabled.
    schedule interval: 1.day, condition: -> { GitHub.enterprise? }

    # prevents multiple jobs from running at the same time
    locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

    def perform(options = {})
      return unless
        GitHub.dotcom_connection_enabled? &&
        GitHub.ghe_usage_metrics_enabled? &&
        GitHub.environment.fetch("ENTERPRISE_ENABLE_ACTIONS_USAGE_STATS", false) == "true"

      GitHub.logger.with_named_tags("gh.job.name" => "ExportGhesActionsJobExecutionsJob", "gh.job.id" => self.job_id) do |logger|
        logger.info("starting export job")
        exporter = GitHub::Connect::ActionsJobExecutionExporter.new

        GitHub.logger.with_named_tags("gh.actions.ghes_job_executions_exporter.total_records" => exporter.total_records) do |logger|
          logger.info("starting export")
          exporter.start
          logger.info("completed export")
        end
      end
    end
  end
end
