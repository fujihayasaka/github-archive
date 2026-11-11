# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    # This job handles destroying seat and seat assignments when they are unassigned from a billable entity on trial.
    class DestroyTrialSeatsJob < CopilotJob
      queue_as :background_destroy
      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

      resolve_tenant_context do |seat_assignment_id|
        seat_assignment = Copilot::SeatAssignment.find_by(id: seat_assignment_id)
        seat_assignment&.owner.is_a?(::Business) ? seat_assignment&.owner : nil
      end

      sig { params(seat_assignment_id: Integer, unassigning_user_id: T.nilable(Integer), reason: Symbol).void }
      def perform(seat_assignment_id, unassigning_user_id: nil, reason: :unassigned_during_trial)
        GitHub.logger.with_named_tags({
          "gh.copilot.seat_assignment.id" => seat_assignment_id,
          "gh.copilot.destroy_trial_seats.reason" => reason,
          "gh.copilot.destroy_trial_seats.unassigning_user_id" => unassigning_user_id
        }) do
          seat_assignment = Copilot::SeatAssignment.find_by(id: seat_assignment_id)

          unless seat_assignment.present?
            GitHub.logger.info("SeatAssignment not found, skipping trial seat cleanup")
            return
          end

          GitHub.logger.info(
            "Processing SeatAssignment for trial seat cleanup",
            "gh.copilot.seat_assignment.assignable_type" => seat_assignment.assignable_type,
            "gh.copilot.seat_assignment.assignable_id" => seat_assignment.assignable_id,
            "gh.copilot.seat_assignment.owner.id" => seat_assignment.owner_id,
            "gh.copilot.seat_assignment.owner.type" => seat_assignment.owner_type,
            "gh.copilot.seat_assignment.seat_count" => seat_assignment.seats.size
          )

          unassigning_user = unassigning_user_id ? ::User.find_by(id: unassigning_user_id) : nil
          destroy_seats_and_assignment!(seat_assignment, unassigning_user, reason)
        end
      rescue => error
        handle_copilot_error(
          Copilot::Errors::SeatAssignmentError.new("Failed to destroy trial seats: #{error.message}"),
          {
            "gh.copilot.seat_assignment.id" => seat_assignment_id,
            "gh.copilot.destroy_trial_seats.unassigning_user_id" => unassigning_user_id,
            "gh.copilot.destroy_trial_seats.reason" => reason,
            "gh.error.message" => error.message,
            "gh.error.backtrace" => error.backtrace&.first(5)
          }
        )
        raise
      end

      private

      sig { params(seat_assignment: Copilot::SeatAssignment, unassigning_user: T.nilable(::User), reason: Symbol).void }
      def destroy_seats_and_assignment!(seat_assignment, unassigning_user, reason)
        seats_count = seat_assignment.seats.size

        GitHub.logger.info(
          "Destroying trial seats and assignment",
          "gh.copilot.seat_assignment.id" => seat_assignment.id,
          "gh.copilot.seats.count" => seats_count
        )

        # memoize customer_id before seats are destroyed
        # Otherwise we lose the owner association on the seat assignment,
        # and this job will emit an error.
        # See https://github.com/github/heart-services/issues/6902
        seats = seat_assignment.seats.includes(:organization, seat_assignment: :owner).load
        seats.each(&:customer_id)

        Copilot::Seat.throttle_writes { seats.destroy_all }
        with_write { seat_assignment.destroy!(actor: unassigning_user) }

        GitHub.logger.info(
          "Successfully destroyed trial seats and assignment",
          "gh.copilot.seat_assignment.id" => seat_assignment.id,
          "gh.copilot.seats.destroyed_count" => seats_count
        )
      end
    end
  end
end
