# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class SeatAssignmentCleanupJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      extend T::Sig
      locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_seat_assignment_job
      exempt_from_tenant_context_requirement

      sig { params(seat_assignment_id: Integer, trial_seats: T::Boolean, staff_actor: T.nilable(::User)).void }
      def perform(seat_assignment_id, trial_seats: false, staff_actor: nil)
        GitHub.logger.with_named_tags({
          "gh.seat_assignment.id" => seat_assignment_id,
        }) do
          seat_assignment = Copilot::SeatAssignment.find_by(id: seat_assignment_id)

          GitHub.logger.info(
            "Loading SeatAssignment to clean up",
            "gh.seat_assignment.present?" => seat_assignment.present?,
            "gh.seat_assignment.pending_cancellation_date" => seat_assignment&.pending_cancellation_date,
            "gh.seat_assignment.pending_cancellation_today?" => seat_assignment&.pending_cancellation_today?,
          )
          return unless seat_assignment.present?
          # If this is being run by stafftools, cancel immediately instead of waiting until the end of the month
          return unless staff_actor || seat_assignment.pending_cancellation_today?

          assignment_type = seat_assignment.symbolized_assignable_type.downcase
          GitHub.dogstats.increment("copilot.seat_assignment_cleanup.to_be_cleaned_up", tags: ["type: #{assignment_type}"])

          GitHub.logger.info("Processing SeatAssignment for cleanup",
                             "gh.org.id" => seat_assignment.organization_id,
                             "gh.copilot.seat_assignment.id" => seat_assignment.id,)

          # If any user associated with the seat assignment being cleaned up should also be associated with
          # another active seat assignment, we should not cancel their seat and instead repoint it at the
          # active seat assignment.
          other_active_assignments_for_owner = SeatAssignment.for_owner(seat_assignment.owner)
                                .where.not(id: seat_assignment.id)
                                .where("pending_cancellation_date > NOW() OR pending_cancellation_date IS NULL")
          with_write do
            seat_assignment.seats.each do |seat|
              if GitHub.flipper[:user_sa_to_team_sa_cleanup_job].enabled?
                other_active_assignments_for_owner.each do |other_assignment|
                  # if this user has a SeatAssignment of any assignable_type that is not also pending cancellation today,
                  # do not cancel their seat. This means that somewhere upstream we didn't handle their seat's
                  # associated SeatAssignment correctly.
                  if other_assignment.includes_user?(seat.assigned_user)
                    # We can point the user's seat to the seat assignment which is still active so they will retain access
                    GitHub.logger.info(
                      "Found #{other_assignment.assignable_type} SeatAssignment containing user that is not pending cancellation. Updating user's seat to point at the active SeatAssignment",
                      "gh.copilot.other_seat_assignment.id" => other_assignment.id,
                      "gh.copilot.seat.id" => seat.id,
                      "gh.user.id" => seat.assigned_user_id,
                    )
                    seat.update(copilot_seat_assignment_id: other_assignment.id)
                    other_assignment_type = other_assignment.symbolized_assignable_type.downcase
                    GitHub.dogstats.increment("copilot.seat_assignment_cleanup.other_active_assignment_found", tags: ["type: #{other_assignment_type}"])

                    # break here because we already found something we want to repoint to
                    break
                  end
                end

                # if this is true, the user's seat wasn't repointed at another active seat assignment above
                seat_not_repointed = seat.copilot_seat_assignment_id == seat_assignment_id

                # passing staff_actor means we're calling this job from stafftools and we don't care about the pending
                # cancellation date or whether things were repointed above
                if seat_not_repointed || staff_actor
                  # If the user's seat wasn't repointed above and is still pending cancellation, we cancel it
                  GitHub.logger.info(
                    "User not found in any other active SeatAssignment. Cancelling user's seat.",
                    "gh.copilot.organization.trial" => trial_seats,
                    "gh.copilot.seat.id" => seat.id,
                    "gh.user.id" => seat.assigned_user_id
                  )
                  seat.cancel!(trial_seat: trial_seats, actor: staff_actor, staff_cancel: !!staff_actor, reason: :seat_assignment_cleaned_up)
                  GitHub.dogstats.increment("copilot.seat_assignment_cleanup.seat_cancelled", tags: ["trial_seats: #{trial_seats}"])
                end
              else
                GitHub.logger.info(
                  "Cancelling associated seat",
                  "gh.copilot.organization.trial" => trial_seats,
                  "gh.copilot.seat.id" => seat.id,
                  "gh.user.id" => seat.assigned_user_id
                )
                # If we're forcing an immediate cancellation, this is coming from Stafftools and we should emit
                # an event saying the seats are being removed by staff by passing staff_actor
                seat.cancel!(trial_seat: trial_seats, actor: staff_actor, staff_cancel: !!staff_actor, reason: :seat_assignment_cleaned_up)
                GitHub.dogstats.increment("copilot.seat_assignment_cleanup.seat_cancelled", tags: ["trial_seats: #{trial_seats}"])
              end
            end
            GitHub.logger.info("Destroying SeatAssignment", "gh.copilot.seat_assignment.id" => seat_assignment_id,)
            seat_assignment.destroy!
          end
        end
      end
    end
  end
end
