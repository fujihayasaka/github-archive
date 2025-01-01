# typed: strict
# frozen_string_literal: true

module Copilot
  class PendingSeatAssignmentsJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
    extend T::Sig

    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
    schedule interval: 24.hours, condition: -> { GitHub.copilot_for_business_enabled? }
    gate_with_feature_flag :copilot_seat_assignment_job
    exempt_from_tenant_context_requirement

    sig { void }
    def perform
      chatterbox_say("Starting Copilot::PendingSeatAssignmentsJob")
      count = 0

      # load up all of the pending seat assignments from today
      Copilot::SeatAssignment.pending_cancellation_today.find_each do |seat_assignment|
        count += 1
        Copilot::SeatManagement::SeatAssignmentCleanupJob.perform_later(T.must(seat_assignment.id))
      end
      chatterbox_say("Finished Copilot::PendingSeatAssignmentsJob - Processed #{count} pending SeatAssignments")
    end
  end
end
