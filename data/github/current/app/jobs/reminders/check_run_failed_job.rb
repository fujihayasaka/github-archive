# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Reminders
  class CheckRunFailedJob < RealTimeJob
    include CiFailed

    PERFORMANCE_THRESHOLD_IN_SECONDS = 5

    resolve_tenant_context do |kwargs|
      check_run = CheckRun.find_by(id: kwargs[:check_run_id])
      repository = check_run&.repository
      if repository
        Business.find_by(id: repository.tenant_id)
      end
    end

    def perform(check_run_id:, event_at:, transaction_id:)
      with_slow_logging(check_run_id: check_run_id) do
        check_run = CheckRun.find(check_run_id)
        return unless check_run.conclusion == "failure"

        pull_requests = check_run.check_suite&.matching_pull_requests.limit(GitHub.duplicate_head_sha_limit) || []
        return if pull_requests.empty?

        events = ci_failed_events(pull_requests, check_run)

        queue_reminder_events(events)
      end
    end

    private

    def with_slow_logging(check_run_id:)
      start = Time.now.to_i

      yield

      duration = Time.now.to_i - start

      if duration > PERFORMANCE_THRESHOLD_IN_SECONDS
        GitHub.logger.info("queueing reminder events took longer than #{PERFORMANCE_THRESHOLD_IN_SECONDS}", {
          "code.namespace" => "Reminders::CheckRunFailedJob",
          "code.function" => "perform",
          "gh.check_run.id" => check_run_id,
        })
      end
      GitHub.dogstats.distribution("reminders_check_run_failed_job_perform", duration)
    end

    def target_name(check_run)
      check_run.visible_name
    end

    def target_url(check_run)
      html_url(check_run.permalink)
    end

    def html_url(suffix)
      GitHub.url + suffix.to_s
    end
  end
end
