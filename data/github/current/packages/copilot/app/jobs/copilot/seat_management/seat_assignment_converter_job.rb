# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class SeatAssignmentConverterJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_seat_assignment_job
      exempt_from_tenant_context_requirement

      sig { params(seat_assignment_id: Integer).void }
      def perform(seat_assignment_id:)
        GitHub.logger.with_named_tags(
          "code.function" => __method__.to_s,
          "code.namespace" => self.class.name,
          "gh.copilot.seat_assignment.id" => seat_assignment_id,
        ) do

          seat_assignment = Copilot::SeatAssignment.find_by(id: seat_assignment_id)

          unless seat_assignment.present?
            GitHub.logger.info("SeatAssignment not found")
            return
          end

          result = with_write do
            seat_assignment.convert_to_seats
          end

          if result.error
            handle_copilot_error(Copilot::Errors::SeatAssignmentError.from_error(result.error), { "gh.copilot.seat_assignment.id" => seat_assignment_id })
          else
            GitHub.logger.info("Converted SeatAssignment to Seats")
          end
        end
      end
    end
  end
end
