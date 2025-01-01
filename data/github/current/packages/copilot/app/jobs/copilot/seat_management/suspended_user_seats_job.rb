# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    # This job processes seats for suspended users. For every seat, it checks if the assigned user is suspended.
    # If the user is suspended, we create a disassociated seat assignment, revoke access and
    # update the seat to point to the disassociated seat assignment
    class SuspendedUserSeatsJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::SeatManagement::SeatAssignmentHelpers
      locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :suspended_user_seats_job
      exempt_from_tenant_context_requirement

      sig { void }
      def perform
        Copilot::Seat.includes(:seat_assignment).find_in_batches(batch_size: 1000) do |batch|
          assigned_ids = batch.map(&:assigned_user_id)
          suspended_ids = ::User.where(id: assigned_ids).where.not(suspended_at: nil).pluck(:id)

          next if suspended_ids.empty?

          batch.each do |seat|
            if suspended_ids.include?(seat.assigned_user_id)
              GitHub.logger.info(
                "Processing seat for suspended user",
                "gh.copilot.seat.id" => seat.id,
                "gh.user.id" => seat.assigned_user_id,
                "gh.copilot.seat_assignment.owner.id" =>  seat.seat_assignment&.owner_id,
                "gh.copilot.seat_assignment.owner_type" =>  seat.seat_assignment&.owner_type,
                "gh.copilot.seat_assignment.assignable_type" =>  seat.seat_assignment&.assignable_type,
              )
              seat_assignment = seat.seat_assignment
              if seat_assignment.nil?
                GitHub.dogstats.increment("copilot.seat_management.suspended_user_seats_job.suspended_user_seat_assignment_missing")
                return
              end

              copilot_owner = seat_assignment.copilot_owner

              if copilot_owner.feature_enabled?(:copilot_revokable_access)
                revoke_seat_assignment_access(seat)
              else
                GitHub.logger.info(
                  "Destroying seat for suspended user",
                  "gh.copilot.seat.id" => seat.id,
                  "gh.user.id" => seat.assigned_user_id,
                  "gh.copilot.seat_assignment.owner.id" =>  seat.seat_assignment&.owner_id,
                  "gh.copilot.seat_assignment.owner_type" =>  seat.seat_assignment&.owner_type,
                  "gh.copilot.seat_assignment.assignable_type" =>  seat.seat_assignment&.assignable_type,
                )
                with_write do
                  seat.cancel!(reason: :assigned_user_suspended)
                  GitHub.dogstats.increment(
                    "copilot.seat_management.suspended_user_seats_job.suspended_user_seat_destroyed"
                  )
                end
              end
            end
          end
        end
      end

      sig { params(seat: Copilot::Seat).void }
      def revoke_seat_assignment_access(seat)
        suspended_seat_assignment = seat.seat_assignment

        if suspended_seat_assignment.nil?
          GitHub.dogstats.increment("copilot.seat_management.suspended_user_seats_job.suspended_user_seat_assignment_missing")
          return
        end

        case suspended_seat_assignment.symbolized_assignable_type
        when :USER
          GitHub.logger.info(
            "Unassigning and revoking access to User seat assignment",
            "gh.copilot.seat.id" => seat.id,
            "gh.user.id" => seat.assigned_user_id,
            "gh.copilot.seat_assignment.id" => suspended_seat_assignment.id
          )

          with_write do
            # this will be a noop if the assignment is already revoked
            suspended_seat_assignment.unassign_and_revoke_access!(nil, :user_suspended)
          end
        when :TEAM, :ORGANIZATION
          GitHub.logger.info(
            "Unassigning and revoking access to #{suspended_seat_assignment.assignable_type.capitalize} seat assignment and creating a disassociated seat assignment",
            "gh.copilot.seat.id" => seat.id,
            "gh.user.id" => seat.assigned_user_id,
            "gh.copilot.seat_assignment.id" => suspended_seat_assignment.id
          )
          with_write do
            disassociated_user_assignment = create_disassociated_seat_assignment(seat.assigned_user_id, seat, suspended_seat_assignment, :suspended_user_disassociate_seat, nil)
            GitHub.logger.info(
              "Associating user's seat with disassociated SeatAssignment",
              "gh.copilot.seat.id" => seat.id,
              "gh.user.id" => seat.assigned_user_id,
              "gh.copilot.seat_assignment.id" => disassociated_user_assignment.id
            )
            disassociated_user_assignment.unassign_and_revoke_access!(nil, :user_suspended)
            seat.update_column(:copilot_seat_assignment_id, disassociated_user_assignment.id)
          end
        end
      end
    end
  end
end
