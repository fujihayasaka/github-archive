# typed: strict
# frozen_string_literal: true

module Copilot
  class TimedPendingSeatAssignmentsJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
    schedule interval: 1.hour, condition: -> { GitHub.copilot_for_business_enabled? }
    gate_with_feature_flag :copilot_timed_seat_assignment_job
    exempt_from_tenant_context_requirement

    sig { void }
    def perform
      # return early unless this job is running in the last hour of the day utc
      return unless Time.current.utc.hour == 23

      GitHub.logger.info("Starting Copilot::TimedPendingSeatAssignmentsJob", "code.function" => "perform")
    end
  end
end
