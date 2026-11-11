# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    # This job is used to uncancel a seat assignments from stafftools for an organization or enterprise,

    class UncancelSeatAssignmentJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers

      STATS_KEY = "copilot.seat_management.uncancel_seat_assignment_job"

      locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

      resolve_tenant_context do |args|
        if args[:seat_assignment_id]
          seat_assignment = Copilot::SeatAssignment.find_by(id: args[:seat_assignment_id])
          case seat_assignment&.owner_type
          when "Organization"
            seat_assignment&.owner&.business
          when "Business"
            seat_assignment&.owner
          else
            nil
          end
        else
          nil
        end
      end

      sig do
        params(
          seat_assignment_id: T.nilable(Integer),
          staff_actor_id: T.nilable(Integer)
        ).void
      end
      def perform(seat_assignment_id: nil, staff_actor_id: nil)
        if seat_assignment_id.nil?
          GitHub.logger.error("No seat_assignment_id provided, exiting job")
          return
        end
        seat_assignment = Copilot::SeatAssignment.find_by(id: seat_assignment_id)
        return unless seat_assignment&.pending_cancellation_date?

        validation = seat_assignment.reinstate_validation("copilot.seat_management.uncancel_seat_assignment_job")

        if validation != :valid
          GitHub.logger.info("Seat assignment cannot be uncancelled", "gh.copilot.seat_assignment.id" => seat_assignment.id, "reason" => validation)
          return
        end

        GitHub.logger.with_named_tags(
          "gh.copilot.seat_assignment.owner_id" => seat_assignment.owner_id,
          "gh.copilot.seat_assignment.owner_type" => seat_assignment.owner_type,
          "gh.copilot.seat_assignment.id" => seat_assignment_id,
        ) do
          with_write do
            seat_assignment.update!(pending_cancellation_date: nil)
            GitHub.logger.info("Successfully removed pending cancellation date for seat assignment", "gh.copilot.seat_assignment.id" => seat_assignment.id)
          rescue StandardError => e
            GitHub.logger.error("Failed to remove pending cancellation date for seat assignment: #{e.message}")
            raise e
          end
          staff_actor = ::User.find_by(id: staff_actor_id) if staff_actor_id.present?
          seat_assignment.seats.find_each do |seat|
            Copilot::Instrumenter.instrument_copilot_for_business_seat_uncancelled(
              seat,
              staff_actor || ::User.staff_user,
            )
          end
        end
      end

    end
  end
end
