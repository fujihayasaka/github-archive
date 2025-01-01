# typed: strict
# frozen_string_literal: true

module Copilot
  class PendingSeatAssignmentsJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
    schedule interval: FeatureFlag.vexi.enabled?(:copilot_seat_assignment_job_eod, default: false) ? 1.hour : 24.hours, condition: -> { GitHub.copilot_for_business_enabled? }
    gate_with_feature_flag :copilot_seat_assignment_job
    exempt_from_tenant_context_requirement

    DAILY_RUN_HOUR = 23

    sig { params(run_now: T::Boolean).void }
    def perform(run_now: false)
      if FeatureFlag.vexi.enabled?(:copilot_seat_assignment_job_eod, default: false)
        # return early unless this job is running in the last hour of the day utc
        unless run_now || Time.current.utc.hour == DAILY_RUN_HOUR
          return
        end
      end

      GitHub.logger.info("Starting Copilot::PendingSeatAssignmentsJob", "code.function" => "perform")
      chatterbox_say("Starting Copilot::PendingSeatAssignmentsJob")
      count = 0

      # load up all of the pending seat assignments from today
      Copilot::SeatAssignment.pending_cancellation_today.find_each do |seat_assignment|
        count += 1
        Copilot::SeatManagement::SeatAssignmentCleanupJob.perform_later(seat_assignment.id)
      end
      GitHub.dogstats.count("copilot.pending_seat_assignments_job.to_be_cancelled", count)
      GitHub.logger.info("Finished Copilot::PendingSeatAssignmentsJob", "code.function" => "perform", "gh.copilot.seat_assignments.count" => count)
    end
  end
end
