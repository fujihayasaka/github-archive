# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class InstrumentSeatAssignmentScheduledCancellationJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

      sig { params(seat_assignment_ids: T::Array[Integer], actor_id: T.nilable(Integer), reason: Symbol).void }
      def perform(seat_assignment_ids, actor_id, reason)
        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.copilot.actor.id" => actor_id,
        ) do
          @seat_assignments = T.let(Copilot::SeatAssignment.where(id: seat_assignment_ids), T.nilable(ActiveRecord::Relation))

          if @seat_assignments.nil? || @seat_assignments.empty?
            return GitHub.logger.info("No seat assignments found")
          end

          @actor = T.let(::User.find_by(id: actor_id), T.nilable(::User))
          GitHub.logger.info("Unassignment not triggered by an actor") unless @actor.present?

          @seat_assignments.each do |assignment|
            Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_unassigned(
              assignment,
              @actor,
              reason
            )
          end

          with_write do
            @seat_assignments.destroy_all
          end
        end
      end
    end
  end
end
