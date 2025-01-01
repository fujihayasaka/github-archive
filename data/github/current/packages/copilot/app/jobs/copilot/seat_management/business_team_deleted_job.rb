# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    # This job handles Copilot seats when a Business Team is deleted.
    # It checks if the team has an assignment to auto-remove (and disassociate) seats.
    class BusinessTeamDeletedJob < CopilotJob
      include Copilot::Helpers
      include Copilot::SeatManagement::SeatAssignmentHelpers
      include Copilot::SeatAssignments::SeatCreation
      gate_with_feature_flag :copilot_business_team_job

      queue_as :copilot
      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      resolve_tenant_context do |args|
        ::BusinessTeam.find_by(id: args[:team_id])&.business
      end

      sig do
        params(
          team_id: Integer,
          business_id: T.nilable(Integer),
          transaction_id: T.nilable(String),
          payload: T.nilable(T::Hash[Symbol, String]),
          actor_id: T.nilable(Integer),
        ).void
      end
      def perform(team_id:, business_id:, transaction_id: nil, payload: nil, actor_id: nil)
        @team_id         = T.let(team_id, T.nilable(Integer))
        @business_id     = T.let(business_id, T.nilable(Integer))
        @transaction_id  = T.let(transaction_id, T.nilable(String))
        @payload         = T.let(payload, T.nilable(T::Hash[Symbol, String]))
        @actor_id        = T.let(actor_id, T.nilable(Integer))
        @actor           = T.let(::User.find_by(id: @actor_id), T.nilable(::User))

        return report_error(Copilot::Errors::MissingBusinessTeamError.new("Invalid BusinessTeam")) unless @team_id

        @business = T.let(::Business.find_by(id: @business_id), T.nilable(::Business))
        return report_error(Copilot::Errors::MissingBusinessError.new("Invalid Business")) unless @business

        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.business.id" => @business_id,
          "gh.business_team.id" => @team_id,
          "gh.instrumentation.transaction_id" => @transaction_id,
          "gh.actor.id" => @actor_id,
        ) do

          @copilot_business = T.let(Copilot::Business.new(@business), T.nilable(Copilot::Business))
          return GitHub.logger.error("Business not enabled for CFB") unless @copilot_business&.copilot_for_business_enabled?

          @team_seat_assignment = T.let(Copilot::SeatAssignment.for_business_team_id(@team_id).first, T.nilable(Copilot::SeatAssignment))

          unless @team_seat_assignment.present?
            GitHub.logger.info("No Business Team SeatAssignment found")
            return
          end

          team_deleted
        end
      end

      private

      sig { void }
      def team_deleted
        GitHub.logger.with_named_tags("code.function" => __method__, "code.namespace" => self.class.name) do
          with_write do
            T.must(@team_seat_assignment).seats.each do |seat|
              handle_seat(seat)
            end

            begin
              T.must(@team_seat_assignment).destroy!
            rescue ActiveRecord::RecordNotFound
              # No action needed, the seat assignment was already destroyed when removing the last seat
            end
          end

          GitHub.dogstats.increment "copilot.business_team_job.team_deleted"
        end
      end

      sig { params(seat: Copilot::Seat).void }
      def handle_seat(seat)
        user = T.must(seat.assigned_user)

        if user.nil?
          GitHub.logger.info("No user found for seat, skipping", "gh.copilot.seat.id" => seat.id)
          return
        end

        if user.suspended?
          unless T.must(@team_seat_assignment).copilot_owner.feature_flag_enabled_or_raise?(:copilot_revokable_access) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            with_write { seat.cancel!(reason: :suspended_user_disassociate_seat) }

            GitHub.logger.info(
              "Seat for suspended user has been canceled",
              "gh.user.id" => user.id,
            )
            return
          end
        else
          # User is not suspended, so we need to check if there are other seat assignments for the user
          # that we can point the seat at.
          other_seat_assignment = other_business_assignment_for_user(T.must(@business), user, T.must(@team_seat_assignment))

          # Found other assignments for the user, so we can repoint the seat to one of them.
          if other_seat_assignment.present?
            with_write do
              seat.update_columns(
                copilot_seat_assignment_id: other_seat_assignment.id,
                organization_id: other_seat_assignment.owner_type == "Organization" ? other_seat_assignment.owner_id : nil
              )
            end

            GitHub.logger.info("Found another SeatAssignment to point Seat at",
              "gh.copilot.seat_assignment.id" => T.must(@team_seat_assignment).id,
              "gh.copilot.other_seat_assignment.id" => other_seat_assignment.id,
              "gh.copilot.seat.id" => seat.id,
              "gh.user.id" => user.id
            )

            GitHub.dogstats.increment "copilot.business_team_job.team_deleted.existing_seat_updated"
            return
          end
        end

        # If the team still exists, that means the team lost access to Copilot.
        disassociate_reason = if BusinessTeam.exists?(id: @team_id)
          :team_unassigned_disassociate_seat
        else
          :team_destroyed_disassociate_seat
        end

        # If we didn't find another assignment, we need to disassociate the seat
        disassociated_user_assignment = create_disassociated_seat_assignment(user.id, seat, T.must(@team_seat_assignment), disassociate_reason, @actor)

        with_write do
          GitHub.logger.info("Associating user's seat with disassociated SeatAssignment",
            "gh.copilot.seat.id" => seat.id,
            "gh.user.id" => user.id,
            "gh.copilot.seat_assignment.id" => disassociated_user_assignment.id
          )
          seat.update_column(:copilot_seat_assignment_id, disassociated_user_assignment.id)

          if disassociated_user_assignment.copilot_owner.feature_flag_enabled_or_raise?(:copilot_revokable_access) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            disassociated_user_assignment.unassign_and_revoke_access!(@actor, disassociate_reason)
          else
            disassociated_user_assignment.unassign!(@actor, disassociate_reason)
          end
        end
      end

      sig do
        params(
          error: Copilot::Errors::CopilotError,
          details: T::Hash[Symbol, T.any(String, Integer, T::Hash[Symbol, String], T.nilable(String))]
        ).void
      end
      def report_error(error, details = {})
        details = details.merge({
          :transaction_id => @transaction_id,
          :payload => @payload,
          "gh.business_team.id" => @team_id,
          "gh.business.id" => @business_id
        })
        GitHub.logger.error(error.message)
        handle_copilot_error(error, details)
      end
    end
  end
end
