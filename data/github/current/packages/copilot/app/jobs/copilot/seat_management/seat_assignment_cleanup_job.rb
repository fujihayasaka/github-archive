# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class SeatAssignmentCleanupJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_seat_assignment_job
      exempt_from_tenant_context_requirement

      sig { params(seat_assignment_id: Integer, trial_seats: T::Boolean, staff_actor: T.nilable(::User)).void }
      def perform(seat_assignment_id, trial_seats: false, staff_actor: nil)
        GitHub.logger.with_named_tags({
          "gh.copilot.seat_assignment.id" => seat_assignment_id,
          "gh.copilot.trial_seats" => trial_seats
        }) do
          seat_assignment = Copilot::SeatAssignment.find_by(id: seat_assignment_id)

          GitHub.logger.info(
            "Loading SeatAssignment to clean up",
            "gh.copilot.seat_assignment.id" => seat_assignment_id,
            "gh.copilot.seat_assignment.pending_cancellation_date" => seat_assignment&.pending_cancellation_date,
            "gh.copilot.seat_assignment.pending_cancellation_today?" => seat_assignment&.pending_cancellation_today?,
            "gh.copilot.seat_assignment.owner.id" => seat_assignment&.owner_id,
            "gh.copilot.seat_assignment.owner_type" => seat_assignment&.owner_type,
          )
          return unless seat_assignment.present?
          # If this is being run by stafftools, cancel immediately instead of waiting until the end of the month
          return unless staff_actor || seat_assignment.pending_cancellation_today?

          assignment_type = seat_assignment.symbolized_assignable_type.downcase
          GitHub.dogstats.increment("copilot.seat_assignment_cleanup.to_be_cleaned_up", tags: ["type:#{assignment_type}"])

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
              assigned_user = seat.assigned_user
              other_active_assignments_for_owner.each do |other_assignment|
                unless should_repoint_seat_for_user?(assigned_user)
                  GitHub.logger.info(
                    "User is suspended, spammy, or no longer exists. Not repointing seat.",
                    "gh.copilot.other_seat_assignment.id" => other_assignment.id,
                    "gh.user.id" => seat.assigned_user_id,
                    "gh.copilot.seat.id" => seat.id,
                    "gh.org.id" => seat_assignment.organization_id,
                    "gh.copilot.seat_assignment.id" => seat_assignment.id
                  )

                  # stop iterating through other assignments, we never want to repoint
                  break
                end

                # if this user still exists and has a SeatAssignment of any assignable_type that is NOT also pending cancellation today,
                # do not cancel their seat. This means that somewhere upstream we didn't repoint their seat assignment correctly.
                if assigned_user && other_assignment.includes_user?(assigned_user)
                  # We can point the user's seat to the seat assignment which is still active so they will retain access
                  GitHub.logger.info(
                    "Found #{other_assignment.assignable_type} SeatAssignment containing user that is not pending cancellation. Updating user's seat to point at the active SeatAssignment",
                    "gh.copilot.other_seat_assignment.id" => other_assignment.id,
                    "gh.copilot.seat.id" => seat.id,
                    "gh.user.id" => seat.assigned_user_id,
                  )
                  seat.update(copilot_seat_assignment_id: other_assignment.id)
                  other_assignment_type = other_assignment.symbolized_assignable_type.downcase
                  GitHub.dogstats.increment("copilot.seat_assignment_cleanup.other_active_assignment_found", tags: ["type:#{other_assignment_type}"])

                  # break here because we already repointed to the first active assignment we found
                  break
                end
              end

              # user's seat wasn't repointed at another active seat assignment above and we need to cancel it
              seat_not_repointed = seat.copilot_seat_assignment_id == seat_assignment_id

              # passing staff_actor means we're calling this job from stafftools and we don't care about the pending
              # cancellation date or whether things were repointed above
              if seat_not_repointed || staff_actor
                # If the user's seat wasn't repointed above and is still pending cancellation, we cancel it
                GitHub.logger.info(
                  "Cancelling user's seat.",
                  "gh.copilot.organization.trial" => trial_seats,
                  "gh.copilot.seat.id" => seat.id,
                  "gh.copilot.seat_assignment.id" => seat_assignment_id,
                  "gh.user.id" => seat.assigned_user_id
                )
                seat.cancel!(trial_seat: trial_seats, actor: staff_actor, staff_cancel: !!staff_actor, reason: :seat_assignment_cleaned_up)
                GitHub.dogstats.increment("copilot.seat_assignment_cleanup.seat_cancelled", tags: ["trial_seats: #{trial_seats}"])
              end
            end
            GitHub.logger.info("Destroying SeatAssignment", "gh.copilot.seat_assignment.id" => seat_assignment_id,)
            seat_assignment.destroy!
          end
        end
      end

      sig { params(user: T.nilable(::User)).returns(T::Boolean) }
      def should_repoint_seat_for_user?(user)
        # we won't repoint the seat to another active assignment if the user is suspended, spammy, or no longer exists;
        # we want to clean up the seat at the end of the billing cycle regardless.
        case
        when user.nil?
          GitHub.dogstats.increment("copilot.seat_assignment_cleanup.repointing_skipped", tags: ["reason:user_deleted"])
          false
        when user.suspended?
          GitHub.dogstats.increment("copilot.seat_assignment_cleanup.repointing_skipped", tags: ["reason:user_suspended"])
          false
        when user.spammy?
          GitHub.dogstats.increment("copilot.seat_assignment_cleanup.repointing_skipped", tags: ["reason:user_spammy"])
          false
        else
          # User exists and is not suspended or spammy
          true
        end
      end
    end
  end
end
