# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    # We have two different events that we can receive.
    #
    # :add_member - the user has been added to the team, so we want to see if the team has an assignment to auto-add
    # :remove_member - the user has been removed from the team, so we want to see if the team has an assignment to auto-remove (and disassociated)
    class BusinessTeamJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers
      include Copilot::SeatManagement::SeatAssignmentHelpers
      include Copilot::SeatAssignments::SeatCreation
      gate_with_feature_flag :copilot_business_team_job

      VALID_ACTIONS = T.let(%i[add_member remove_member], T::Array[Symbol])

      resolve_tenant_context do |args|
        ::BusinessTeam.find_by(id: args[:team_id])&.business
      end

      sig do
        params(
          team_id: Integer,
          user_id: T.nilable(Integer),
          action: Symbol,
          transaction_id: T.nilable(String),
          payload: T.nilable(T::Hash[Symbol, String]),
          actor_id: T.nilable(Integer),
        ).void
      end
      def perform(team_id:, user_id: nil, action: :unknown, transaction_id: nil, payload: nil, actor_id: nil)
        raise ArgumentError, "Invalid action: #{action}" unless VALID_ACTIONS.include?(action)

        @team_id         = T.let(team_id, T.nilable(Integer))
        @action          = T.let(action, T.nilable(Symbol))
        @transaction_id  = T.let(transaction_id, T.nilable(String))
        @payload         = T.let(payload, T.nilable(T::Hash[Symbol, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped
        @actor_id        = T.let(actor_id, T.nilable(Integer))
        @actor           = T.let(::User.find_by(id: @actor_id), T.nilable(::User))

        @user_id = T.let(user_id, T.nilable(Integer))
        @user = T.let(::User.find_by(id: T.must(@user_id)), T.nilable(::User))
        return report_error(Copilot::Errors::SeatCreationError.new("Invalid User")) unless @user

        @business_team = T.let(::BusinessTeam.find_by(id: T.must(@team_id)), T.nilable(::BusinessTeam))
        return report_error(Copilot::Errors::MissingBusinessTeamError.new("Invalid BusinessTeam")) unless @business_team

        @business = T.let(@business_team.business, T.nilable(::Business))
        return report_error(Copilot::Errors::MissingBusinessError.new("Invalid Business")) unless @business

        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.business.id" => @business.id,
          "gh.business_team.id" => @business_team.id,
          "gh.user.id" => @user_id,
          "gh.copilot.job_action" => action,
          "gh.instrumentation.transaction_id" => @transaction_id,
          "gh.actor.id" => @actor_id,
        ) do
          copilot_business = Copilot::Business.new(@business)
          return GitHub.logger.error("Business not enabled for CFB") unless copilot_business.copilot_for_business_enabled?

          @team_seat_assignment = T.let(Copilot::SeatAssignment.for_business_team(@business_team).first, T.nilable(Copilot::SeatAssignment))

          unless @team_seat_assignment.present?
            GitHub.logger.info("No Business Team SeatAssignment found")
            return
          end

          GitHub.logger.info("Processing action")
          case action
          when :add_member
            member_added
          when :remove_member
            member_removed
          else
            raise ArgumentError, "Invalid action: #{action}"
          end
        end
      end

      private

      # A member was added to the team. Ensure the user has a seat assigned, and their seat is not pending cancellation.
      sig { void }
      def member_added
        GitHub.logger.with_named_tags("code.function" => __method__, "code.namespace" => self.class.name) do
          # This function returns both Business and Organization owned seats.
          # It searches business owned orgs for Organization owned seats.
          business_or_org_existing_seat = Copilot::Seat.for_business_user_ids(T.must(@business), T.must(@user).id).first

          if business_or_org_existing_seat.present?
            GitHub.logger.info("Existing Seat found for User")
            GitHub.dogstats.increment "copilot.business_team_job.member_added.exists"

            # First, we need to check if the user has an existing seat assignment
            existing_seat_assignment = business_or_org_existing_seat.seat_assignment

            if business_or_org_existing_seat.pending_cancellation_date.present?
              # The existing seat has a valid assignment but is pending cancellation, so we need to update it to point at the team assignment.
              GitHub.logger.info("Existing Seat pending cancellation was found, updating it to point at BusinessTeam SeatAssignment",
                  "gh.copilot.seat_assignment.id" => T.must(@team_seat_assignment).id,
                  "gh.copilot.other_seat_assignment.id" => existing_seat_assignment.id,
                  "gh.copilot.seat_assignment.symbolized_assignable_type" => existing_seat_assignment.symbolized_assignable_type,
                  "gh.copilot.seat.id" => business_or_org_existing_seat.id,
                  "gh.user.id" => @user&.id)
            else
              # Has a valid seat assignment, and it is not pending cancellation. No action needed.
              return
            end

            with_write do
              business_or_org_existing_seat.update_columns(
                copilot_seat_assignment_id: T.must(@team_seat_assignment).id,
                organization_id: nil # BusinessTeam SeatAssignments are not associated with an Organization
              )
            end

            GitHub.dogstats.increment "copilot.business_team_job.member_added.existing_seat_updated"

            if existing_seat_assignment.access_revoked?
              # We're implictly reinstating access, so we just log
              existing_seat_assignment.log_reinstatement_and_refund_user(:user_added_to_business_team)
            end

            if existing_seat_assignment.seats.empty?
              GitHub.logger.info("Old SeatAssignment has no associated seats anymore, destroying it.",
                                  "gh.copilot.other_seat_assignment.id" => existing_seat_assignment.id,
                                  "gh.copilot.seat_assignment.id" => T.must(@team_seat_assignment).id)
              with_write do
                existing_seat_assignment.destroy!
              end
            end

            # No further action needed, the existing seat is now associated with the team assignment.
            return
          end

          # No seat found. insert_seats will create the seat, instrument the CfB seat addition,
          # call SeatAssignedJob, look for and activate trials and more
          insert_seats(
            [
              {
                assigned_user_id: @user&.id,
                copilot_seat_assignment_id: T.must(@team_seat_assignment).id,
                organization_id: nil, # BusinessTeam SeatAssignments are not associated with an Organization
              }
            ],
            T.must(@team_seat_assignment)
          )

          GitHub.logger.info(
            "Created seat for user with BusinessTeam SeatAssignment",
            "gh.copilot.seat_assignment.id" => T.must(@team_seat_assignment).id
          )
        end
      end

      # A member was removed from the team. Check if they still need a seat, and if there's another assignment we can point the seat at.
      sig { void }
      def member_removed
        GitHub.logger.with_named_tags("code.function" => __method__, "code.namespace" => self.class.name) do
          existing_seats = Copilot::Seat.for_business_user_ids(T.must(@business), T.must(@user).id)

          seat = existing_seats.find { |s| s.seat_assignment == @team_seat_assignment }

          unless seat.present?
            GitHub.logger.info(
              "User seat doesn't exist for this Business Team SeatAssignment",
              "gh.user.id" => T.must(@user).id,
              "gh.business.id" => T.must(@business).id,
              "gh.business_team.id" => T.must(@business_team).id,
            )
            return
          end

          # If the user is suspended, just cancel their seat and exit
          if T.must(@user).suspended?
            unless T.must(@team_seat_assignment).copilot_owner.feature_flag_enabled_or_raise?(:copilot_revokable_access) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
              with_write { seat.cancel!(reason: :suspended_user_disassociate_seat) }

              GitHub.logger.info(
                "Seat for suspended user has been canceled",
                "gh.user.id" => T.must(@user).id,
              )
              return
            end
          else
            # User is not suspended, so we need to check if there are other seat assignments for the user
            # that we can point the seat at.
            other_seat_assignment = other_business_assignment_for_user(T.must(@business), T.must(@user), T.must(@team_seat_assignment))

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
                "gh.user.id" => T.must(@user).id
              )

              GitHub.dogstats.increment "copilot.business_team_job.member_removed.existing_seat_updated"
              return
            end
          end

          # If we didn't find another assignment, we need to disassociate the seat
          disassociated_user_assignment = create_disassociated_seat_assignment(T.must(@user).id, seat, T.must(@team_seat_assignment), :team_member_removed_disassociate_seat, @actor)

          with_write do
            GitHub.logger.info("Associating user's seat with disassociated SeatAssignment",
              "gh.copilot.seat.id" => seat.id,
              "gh.user.id" => T.must(@user).id,
              "gh.copilot.seat_assignment.id" => disassociated_user_assignment.id
            )
            seat.update_column(:copilot_seat_assignment_id, disassociated_user_assignment.id)

            if disassociated_user_assignment.copilot_owner.feature_flag_enabled_or_raise?(:copilot_revokable_access) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
              disassociated_user_assignment.unassign_and_revoke_access!(@actor, :team_member_removed_disassociate_seat)
            else
              disassociated_user_assignment.unassign!(@actor, :team_member_removed_disassociate_seat)
            end
          end
        end
      end

      sig { params(error: Copilot::Errors::CopilotError, details: T::Hash[Symbol, T.untyped]).void } # rubocop:disable Sorbet/ForbidTUntyped
      def report_error(error,  details = {})
        details = details.merge({
          :action => @action,
          :transaction_id => @transaction_id,
          :payload => @payload,
          "gh.business_team.id" => @team_id,
          "gh.user.id" => @user_id,
        })
        if @business && @business.id
          details["gh.business.id"] = @business.id
        end
        GitHub.logger.error(error.message)
        handle_copilot_error(error, details)
      end
    end
  end
end
