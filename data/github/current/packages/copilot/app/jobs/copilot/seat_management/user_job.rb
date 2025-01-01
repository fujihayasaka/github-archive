# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class UserJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      extend T::Sig
      include Copilot::Helpers
      gate_with_feature_flag :copilot_seat_assignment_job

      sig do
        params(
          user_id: Integer,
          transaction_id: T.nilable(String),
          action: Symbol,
          payload: T.nilable(T::Hash[Symbol, T.untyped]), # rubocop:disable Sorbet/ForbidTUntyped
          actor_id: T.nilable(Integer)
        ).void
      end
      def perform(user_id:, transaction_id: nil, action: :destroy, payload: nil, actor_id: nil)
        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.copilot.job_action" => action,
          "gh.instrumentation.transaction_id" => transaction_id,
          "gh.user.id" => user_id,
        ) do
          @user_id         = T.let(user_id, T.nilable(Integer))
          @action          = T.let(action, T.nilable(Symbol))
          @transaction_id  = T.let(transaction_id, T.nilable(String))
          @payload         = T.let(payload, T.nilable(T::Hash[Symbol, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped
          @actor_id        = T.let(actor_id, T.nilable(Integer))

          case action
          when :destroy
            GitHub.logger.info("Loading CFB Seats for User")
            seats = Copilot::Seat.where(assigned_user_id: @user_id)

            if seats.count > 0
              GitHub.logger.info(
                "Loaded CFB Seats for User",
                "gh.copilot.seats.count" => seats.count,
                "gh.copilot.organization_ids" => seats.map(&:organization_id).join(","),
              )

              with_write do
                seats.destroy_all # need to call this because the notifications won't work - there is no user any more (pour one out)
              end
            else
              GitHub.logger.info("No CFB Seats Found For User")
            end

            GitHub.logger.info("Loading User Level CFB Seat Assignments For User")
            seat_assignments = Copilot::SeatAssignment.where(assignable_type: "User", assignable_id: @user_id)

            if seat_assignments.count > 0
              GitHub.logger.info(
                "Loaded User Level CFB Seat Assignments For User",
                "gh.copilot.seat_assignments.count" => seat_assignments.count,
                "gh.copilot.organization.ids" => seat_assignments.map(&:organization_id).join(","),
              )
              with_write do
                seat_assignments.destroy_all
              end
            else
              GitHub.logger.info("No User Level CFB Seat Assignments For User")
            end

          else
            raise ArgumentError, "Invalid action: #{action}"
          end
        end
      end

      sig { params(message: String).void }
      def report_error(message)
        details = {
          :action => @action,
          :transaction_id => @transaction_id,
          :payload => @payload,
          "gh.user.id" => @user_id,
          "gh.actor.id" => @actor_id,
        }
        handle_error(message, details)
      end
    end
  end
end
