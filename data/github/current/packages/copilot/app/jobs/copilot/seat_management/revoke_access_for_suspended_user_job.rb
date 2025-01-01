# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class RevokeAccessForSuspendedUserJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers
      include Copilot::SeatManagement::SeatAssignmentHelpers
      # using this flag name so it is not confused with the SuspendedUserSeatsJob, which is a scheduled job
      # that this job will replace in the future
      gate_with_feature_flag :copilot_revokable_suspended_user_job

      locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

      resolve_tenant_context do |args|
        ::User.find_by(id: args[:user_id])&.enterprise_managed_business
      end

      sig do
        params(
          user_id: Integer,
          transaction_id: T.nilable(String),
          payload: T.nilable(T::Hash[Symbol, T.untyped]), # rubocop:disable Sorbet/ForbidTUntyped
          actor_id: T.nilable(Integer)
        ).void
      end
      def perform(user_id:, transaction_id: nil, payload: nil, actor_id: nil)
        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.copilot.job_action" => :suspend,
          "gh.instrumentation.transaction_id" => transaction_id,
          "gh.user.id" => user_id,
        ) do
          @user_id         = T.let(user_id, T.nilable(Integer))
          @transaction_id  = T.let(transaction_id, T.nilable(String))
          @payload         = T.let(payload, T.nilable(T::Hash[Symbol, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped
          @actor_id        = T.let(actor_id, T.nilable(Integer))

          seats = Copilot::Seat.includes(:seat_assignment).where(assigned_user_id: @user_id)

          if seats.any?
            GitHub.logger.info(
              "Loaded Copilot Seats for user",
              "gh.copilot.seats.count" => seats.count,
              "gh.copilot.organization_ids" => seats.map(&:owner_id).join(","),
            )
          else
            GitHub.logger.info("No Copilot Seats Found for user")
          end

          seats.each do |seat|
            seat_assignment = seat.seat_assignment

            if seat_assignment.nil?
              # we didn't find a seat_assignment for the seat, this is unlikely but let's tell someone
              # we don't need to clean this seat up from here because the DeleteOrphanedSeatJob will get it
              report_error("Seat assignment not found for seat with id #{seat.id}")
              next
            end

            if seat_assignment.copilot_owner&.feature_flag_enabled_or_raise?(:copilot_revokable_access) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
              revoke_seat_for_user(seat_assignment, seat, "suspended_user_job", :user_suspended)
            else
              GitHub.logger.info(
                "Skipping handling seat assignment for suspended user, revokable access not enabled for owner",
                "gh.copilot.seat_assignment.id" => seat_assignment.id,
                "gh.user.id" => @user_id,
              )
            end
          end
        end
      end

      sig { params(message: String).void }
      def report_error(message)
        # rubocop:disable Style/HashSyntax
        details = {
          action: :suspend,
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
