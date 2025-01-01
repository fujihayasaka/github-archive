# typed: strict
# frozen_string_literal: true

module Copilot
  class DeleteOrphanedSeatsJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
    schedule interval: 1.hour, condition: -> { GitHub.copilot_for_business_enabled? }
    gate_with_feature_flag :copilot_seat_assignment_job
    # This job runs over ALL orphaned seats, and should not be explicitly tied to a particular tenant.
    exempt_from_tenant_context_requirement

    sig { void }
    def perform
      count = 0

      deletable = seats_to_delete

      if deletable.any?
        deletable.find_each do |seat|
          count += 1
          with_write do
            GitHub.dogstats.increment("copilot.delete_orphaned_seats_job.seat_deleted")
            GitHub.logger.info("Deleting orphaned Seat", "gh.copilot.seat.id" => seat.id) do
              seat.destroy!
            end
          end
        end

        GitHub.logger.info("Finished Copilot::DeleteOrphanedSeatsJob", "gh.copilot.delete_orphaned_seats_job.deleted_count" => count)
      end
    end

    # 100% i extracted this for the rhyme - PV
    sig { returns(ActiveRecord::Relation) }
    def seats_to_delete
      GitHub.logger.info("Loading orphaned seats to delete")
      Copilot::Seat
      .joins("left join copilot_seat_assignments on copilot_seat_assignments.id = copilot_seats.copilot_seat_assignment_id")
      .where("copilot_seat_assignments.id is null")
    end
  end
end
