# typed: strict
# frozen_string_literal: true

module Copilot
  class DeleteOrphanedSeatsJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
    schedule interval: 1.hour, condition: -> { GitHub.copilot_for_business_enabled? }
    gate_with_feature_flag :copilot_delete_orphaned_seats_job
    # This job runs over ALL orphaned seats, and should not be explicitly tied to a particular tenant.
    exempt_from_tenant_context_requirement

    # Number of copilot_seats primary-key values scanned per anti-join statement. The sweep advances
    # its window cursor by this fixed amount (NOT by the last matched id), so a single statement can
    # examine at most WINDOW_SIZE copilot_seats rows regardless of how sparse the orphans are: the
    # `id <= hi` bound caps the range scan even when the batch LIMIT is never reached. This keeps
    # every statement short enough to avoid the ~12s pt-kill on the copilot cluster (which has no MET).
    WINDOW_SIZE = T.let(50_000, Integer)

    sig { void }
    def perform
      GitHub.logger.info("Loading orphaned seats to delete")

      lo = Copilot::Seat.minimum(:id).to_i - 1
      max_id = Copilot::Seat.maximum(:id).to_i
      count = 0

      while lo < max_id
        hi = lo + window_size

        orphans_in_window(lo, hi).find_each do |seat|
          count += 1
          with_write do
            GitHub.logger.info(
              "Deleting orphaned Seat",
              "gh.copilot.seat.id" => seat.id,
              "gh.user.id" => seat.assigned_user_id,
              "gh.copilot.seat_assignment.id" => seat.copilot_seat_assignment_id,
              "gh.org.id" => seat.organization_id
            )

            seat.destroy!
            GitHub.dogstats.increment("copilot.delete_orphaned_seats_job.seat_deleted")
          end
        end

        lo = hi
      end

      if count.positive?
        GitHub.logger.info("Finished Copilot::DeleteOrphanedSeatsJob", "gh.copilot.delete_orphaned_seats_job.deleted_count" => count)
      end
    end

    # Orphaned == the FK points to a copilot_seat_assignments row that no longer exists. Bounded to a
    # fixed primary-key window (lo, hi] so each statement examines at most WINDOW_SIZE seat rows.
    sig { params(lo: Integer, hi: Integer).returns(ActiveRecord::Relation) }
    def orphans_in_window(lo, hi)
      Copilot::Seat
        .joins("left join copilot_seat_assignments on copilot_seat_assignments.id = copilot_seats.copilot_seat_assignment_id")
        .where("copilot_seat_assignments.id is null")
        .where("copilot_seats.id > ? and copilot_seats.id <= ?", lo, hi)
    end

    private

    sig { returns(Integer) }
    def window_size
      WINDOW_SIZE
    end
  end
end
