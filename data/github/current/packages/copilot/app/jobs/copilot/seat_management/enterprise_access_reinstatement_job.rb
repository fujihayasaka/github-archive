# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class EnterpriseAccessReinstatementJob < CopilotJob
      include Copilot::Helpers

      STATS_KEY = "copilot.seat_management.enterprise_access_reinstatement_job"

      locked_by timeout: 5.minutes, key: ->(job) {
        job.arguments[0][:enterprise_id]
      }
      gate_with_feature_flag :copilot_basic_enterprise_access_reinstatement_job

      queue_as :copilot_enterprise_access_reinstatement_job

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      resolve_tenant_context do |args|
        ::Business.find_by(id: args[:enterprise_id])
      end

      sig { params(enterprise_id: Integer, reason: Symbol, transaction_id: T.nilable(Integer), payload: T.nilable(T::Hash[Symbol, String]), actor_id: T.nilable(Integer)).void }
      def perform(enterprise_id:, reason:, transaction_id: nil, payload: nil, actor_id: nil)
        GitHub.logger.with_named_tags(
          "gh.business.id" => enterprise_id,
          "gh.copilot.reason" => reason,
          "transaction_id" => transaction_id,
          "actor_id" => actor_id
        ) do
          # First check the enterprise exists
          @enterprise = T.let(::Business.find_by(id: enterprise_id), T.nilable(::Business))
          return handle_copilot_error(
            Copilot::Errors::MissingBusinessError.new("Enterprise cannot be found.")
          ) unless @enterprise

          copilot_business = Copilot::Business.new(@enterprise)

          # Get all revoked seat assignments for the enterprise
          seat_assignments = Copilot::SeatAssignment
            .includes(:assignable)
            .for_owner(@enterprise)
            .where.not(access_revoked_at: nil)

          # No seat assignments, nothing to reinstate.
          if seat_assignments.empty?
            GitHub.logger.info("No seat assignments with revoked access to restore, exiting")
            GitHub.dogstats.increment("#{STATS_KEY}.skipped", tags: ["reason:no_seat_assignments_revoked"])
            return
          end

          # Get all the current enterprise team ids for Copilot that are associated with the enterprise.
          current_enterprise_teams_ids = EnterpriseTeam.owned_by(@enterprise).pluck(:id)

          # Get all the current business team ids for Copilot that are associated with the enterprise.
          # Only populated when the feature flag is enabled.
          current_business_team_ids = if FeatureFlag.vexi.enabled?(:copilot_reinstate_to_business_team, @enterprise, default: false)
            BusinessTeam.where(business_id: @enterprise.id).pluck(:id)
          else
            []
          end

          # Group assignments by type and access status
          grouped_assignments = group_seat_assignments(seat_assignments, current_enterprise_teams_ids, current_business_team_ids)

          teams_to_skip = grouped_assignments.fetch(:teams_to_skip, []) + grouped_assignments.fetch(:business_teams_to_skip, [])

          # At this point, we know Copilot is enabled for the enterprise and they have at least
          # one seat assignment with revoked access — we can attempt to reinstate the assignment's access.
          GitHub.logger.info("Reinstating access to seat assignments")

          # First we'll attempt to reinstate the access for the teams that are still associated with the enterprise.
          teams_count = grouped_assignments.fetch(:teams_to_reinstate, []).inject(0) do |count, assignment|
            next count unless assignment.assignable.present?

            GitHub.logger.info("Reinstating access to enterprise team seat assignment",
                               "gh.enterprise_team.id" => assignment.assignable_id,
                               "gh.copilot.seat_assignment.id" => assignment.id)

            with_write do
              assignment.reinstate_access!(
                reason,
                options: { allow_non_user: true, uncancel: copilot_business.copilot_enabled? }
              )
            end

            GitHub.dogstats.increment("#{STATS_KEY}.enterprise_team_reinstatement.success")

            count + 1
          end

          # Reinstate the access for the business teams that are still associated with the enterprise.
          business_teams_count = grouped_assignments.fetch(:business_teams_to_reinstate, []).inject(0) do |count, assignment|
            next count unless assignment.assignable.present?

            GitHub.logger.info("Reinstating access to business team seat assignment",
                               "gh.business_team.id" => assignment.assignable_id,
                               "gh.copilot.seat_assignment.id" => assignment.id)

            with_write do
              assignment.reinstate_access!(
                reason,
                options: { allow_non_user: true, uncancel: copilot_business.copilot_enabled? }
              )
            end

            GitHub.dogstats.increment("#{STATS_KEY}.business_team_reinstatement.success")

            count + 1
          end

          repointed_count = 0

          user_count = grouped_assignments.fetch(:user, []).inject(0) do |count, assignment|
            # If there is no user, there is nothing to reinstate; they will be billed for the seat,
            # and the seat and assignment will be deleted at the end of the billing cycle.
            log_details = { "gh.user.id" => assignment.assignable_id, "gh.copilot.seat_assignment.id" => assignment.id }

            unless assignment.assignable.present?
              GitHub.logger.info("User is missing", log_details)
              GitHub.dogstats.increment("#{STATS_KEY}.user.skipped", tags: ["reason:user_missing"])
              next count
            end

            # Same thing here, if the user is suspended, we can't reinstate access.
            if assignment.assignable.suspended?
              GitHub.logger.info("User is suspended", log_details)
              GitHub.dogstats.increment("#{STATS_KEY}.user.skipped", tags: ["reason:user_suspended"])
              next count
            end

            # If the user is not a member of the enterprise, we can't reinstate access.
            unless @enterprise.unaffiliated_member?(assignment.assignable)
              GitHub.logger.info("User is not a member of the enterprise", log_details)
              GitHub.dogstats.increment("#{STATS_KEY}.user.skipped", tags: ["reason:not_in_enterprise"])
              next count
            end

            user_enterprise_teams = T.let([], T::Array[Integer])

            # Enterprise teams are only available to standalone businesses.
            if copilot_business.is_standalone_business?
              # Is the user still a member of any existing enterprise teams?
              user_enterprise_teams = all_enterprise_teams_for_user(assignment.assignable.id, current_enterprise_teams_ids)
            end

            # Is the user still a member of any existing business teams?
            user_business_teams = all_business_teams_for_user(assignment.assignable.id, current_business_team_ids)

            # There is no team, now we can try to reinstate their user assignment
            if user_enterprise_teams.empty? && user_business_teams.empty?
              GitHub.logger.info("User doesn't belong to an enterprise team within the enterprise", log_details)

              if copilot_business.is_standalone_business?
                GitHub.logger.info("Standalone enterprise users can't be reinstated without an enterprise team", log_details)
                GitHub.dogstats.increment("#{STATS_KEY}.user.skipped",  tags: ["reason:no_enterprise_team"])
                next count
              end

              unless can_reinstate_individual_seat_assignments?(copilot_business.business_object, reason)
                GitHub.logger.info("Enterprise users can't be reinstated without copilot_reinstate_user_assignments_without_teams enabled", log_details)
                GitHub.dogstats.increment("#{STATS_KEY}.user.skipped",  tags: ["reason:feature_flag_disabled_for_user_without_team"])
                next count
              end

              # If we get this far, this is a enterprise user assignment
              GitHub.logger.info("Reinstating enterprise user seat assignment",
                "gh.enterprise_user.id" => assignment.assignable_id,
                "gh.copilot.seat_assignment.id" => assignment.id
              )

              with_write do
                assignment.reinstate_access!(
                  reason,
                  options: { uncancel: assignment.assignable.feature_flag_enabled?(:copilot_uncancel_direct_assignment_on_reinstatement, default: false) }
                )
              end

              GitHub.dogstats.increment("#{STATS_KEY}.enterprise_user_reinstatement.success")

              Copilot::Cache::SeatsCheckClient.new(user: assignment.assignable).invalidate("enterprise_access_reinstated")
              Copilot::Cache::SeatAssignmentsRevokedCheckClient.new(user: assignment.assignable).invalidate("enterprise_access_reinstated")

              count + 1
            else
              # The user belongs to at least one team, try to repoint the seat to a team assignment
              team_assignments = Copilot::SeatAssignment.where(
                assignable_id: user_enterprise_teams,
                assignable_type: "EnterpriseTeam"
              )

              business_team_assignments = Copilot::SeatAssignment.where(
                assignable_id: user_business_teams,
                assignable_type: "BusinessTeam"
              )

              # They belong to a team, but that team doesn't have a seat assignment.
              if team_assignments.empty? && business_team_assignments.empty?
                GitHub.logger.info("User doesn't belong to an enterprise team with Copilot access", log_details)
                GitHub.dogstats.increment("#{STATS_KEY}.user.skipped",  tags: ["reason:no_enterprise_team_seat_assignment"])
                next count
              end

              first_assignment = team_assignments.first || business_team_assignments.first
              first_assignment = T.must(first_assignment)

              with_write do
                # Repoint the seat to the first team assignment of which the user is a member
                # T.must should be safe here as we just checked that the array was not empty.
                assignment.seats.update_all(copilot_seat_assignment_id: first_assignment.id)
                # Destroy the old revoked assignment
                assignment.destroy
              end

              GitHub.logger.info("Repointed user seat assignment to team assignment",
                "gh.user.id" => assignment.assignable.id,
                "gh.copilot.old_seat_assignment.id" => assignment.id,
                "gh.enterprise_team.id" => first_assignment.assignable_id,
                "gh.copilot.new_seat_assignment.id" => first_assignment.id,
              )
              GitHub.dogstats.increment("#{STATS_KEY}.user_seat_repoint.success")

              Copilot::Cache::SeatsCheckClient.new(user: assignment.assignable).invalidate("enterprise_access_repoint")
              Copilot::Cache::SeatAssignmentsRevokedCheckClient.new(user: assignment.assignable).invalidate("enterprise_access_repoint")

              repointed_count += 1
            end
          end

          total_reinstated_count = teams_count + business_teams_count + user_count

          if total_reinstated_count > 0
            GitHub.logger.info(
              "Reinstated access to seat assignments",
              "gh.copilot.seat_assignment.reinstated_count" => total_reinstated_count,
              "gh.copilot.seat.repointed_count" => repointed_count,
            )
          elsif teams_to_skip.any?
            GitHub.logger.info("Skipping reinstatement of seat assignments",
              "gh.copilot.seat_assignment.skipped_ids" => teams_to_skip.map(&:id),
            )
          end
          GitHub.dogstats.increment("#{STATS_KEY}.success")
        end
      end

      private

      sig { params(business: ::Business, reason: Symbol).returns(T::Boolean) }
      def can_reinstate_individual_seat_assignments?(business, reason)
        business.feature_flag_enabled?(:copilot_reinstate_user_assignments_without_teams, default: false) || reason == :staff_forced_reinstatement
      end

      sig { params(user_id: Integer, enterprise_team_ids: T::Array[Integer]).returns(T::Array[Integer]) }
      def all_enterprise_teams_for_user(user_id, enterprise_team_ids)
        direct_membership_ids = EnterpriseTeamMembership
          .where(user_id: user_id, enterprise_team_id: enterprise_team_ids)
          .select(:enterprise_team_id)
          .pluck(:enterprise_team_id)

        unless direct_membership_ids.empty?
          return EnterpriseTeam.where(id: direct_membership_ids).pluck(:id)
        end

        EnterpriseTeam
          .where(id: enterprise_team_ids)
          .joins(enterprise_team_group_mappings: { external_group: { external_identity_group_memberships: :external_identity } })
          .where(external_identities: { user_id: user_id })
          .merge(ExternalIdentity.is_active)
          .pluck(:id)
      end

      sig { params(user_id: Integer, business_team_ids: T::Array[Integer]).returns(T::Array[Integer]) }
      def all_business_teams_for_user(user_id, business_team_ids)
        return [] if business_team_ids.empty?

        Ability
          .where(subject_type: "BusinessTeam", actor_type: "User", actor_id: user_id, subject_id: business_team_ids)
          .pluck(:subject_id)
          .uniq
      end

      sig do
        params(
          seat_assignments: ActiveRecord::Relation,
          team_ids: T::Array[Integer],
          business_team_ids: T::Array[Integer]
        )
        .returns(T::Hash[Symbol, T::Array[Copilot::SeatAssignment]])
      end
      def group_seat_assignments(seat_assignments, team_ids, business_team_ids)
        seat_assignments.group_by do |assignment|
          if assignment.assignable_type == "User"
            :user
          elsif assignment.assignable_type == "EnterpriseTeam"
            if team_ids.include?(assignment.assignable_id)
              :teams_to_reinstate
            else
              :teams_to_skip
            end
          elsif assignment.assignable_type == "BusinessTeam"
            if business_team_ids.include?(assignment.assignable_id)
              :business_teams_to_reinstate
            else
              :business_teams_to_skip
            end
          else
            # We should never hit this case.
            :other
          end
        end
      end
    end
  end
end
