# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateTeamReviewAssignment < Platform::Mutations::Base
      description "Updates team review assignment."

      minimum_accepted_scopes ["write:org"]

      argument :id, ID, "The Node ID of the team to update review assignments of", required: true, loads: Objects::Team, as: :team
      argument :enabled, Boolean, "Turn on or off review assignment", required: true
      argument :algorithm, Enums::TeamReviewAssignmentAlgorithm, "The algorithm to use for review assignment", required: false, default_value: T.must(Platform::Enums::TeamReviewAssignmentAlgorithm.values["ROUND_ROBIN"]).value
      argument :team_member_count, Integer, "The number of team members to assign", required: false, default_value: 1
      argument :notify_team, Boolean, "Notify the entire team of the PR if it is delegated", required: false, default_value: true
      argument :remove_team_request, Boolean, "Remove the team review request when assigning", required: false, default_value: true
      argument :include_child_team_members, Boolean, "Include the members of any child teams when assigning", required: false, default_value: true
      argument :count_members_already_requested, Boolean, "Count any members whose review has already been requested against the required number of members assigned to review", required: false, default_value: true
      argument :excluded_team_member_ids, [ID], "An array of team member IDs to exclude", required: false, loads: Objects::User

      field :team, Objects::Team, "The team that was modified", null: true

      def self.async_api_can_modify?(permission, team:, **inputs)
        team.async_organization.then do |organization|
          permission.access_allowed?(:v4_manage_team, resource: team, team: team, organization: organization, current_repo: nil, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(team:, **inputs)
        actor = context[:actor]
        viewer = context[:viewer]

        unless team.updatable_by?(actor)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to update this team.")
        end

        team.review_request_delegation_notify_team = inputs[:notify_team]

        if inputs[:enabled]
          unless !!inputs[:algorithm] && !!inputs[:team_member_count]
            raise Errors::Unprocessable.new("Algorithm and team member count needed when enabling.")
          end

          team.review_request_delegation_enabled = true
          team.review_request_delegation_algorithm = inputs[:algorithm]
          team.review_request_delegation_member_count = inputs[:team_member_count]
          team.review_request_delegation_remove_team_request = inputs[:remove_team_request]
          team.review_request_delegation_include_child_team_members = inputs[:include_child_team_members]
          team.review_request_delegation_count_members_already_requested = inputs[:count_members_already_requested]

          ReviewRequestDelegationExcludedMember.transaction do
            ReviewRequestDelegationExcludedMember.where(team: team).delete_all

            if inputs[:excluded_team_members]
              to_create = inputs[:excluded_team_members].map do |member|
                { user: member, team: team }
              end

              ReviewRequestDelegationExcludedMember.create!(to_create)
            end
          rescue ActiveRecord::RecordInvalid
            raise Errors::Unprocessable.new("Could not update excluded members")
          end
        else
          team.review_request_delegation_enabled = false
        end

        if team.save
          { team: team }
        else
          raise Errors::Unprocessable.new(team.errors.full_messages.join(", "))
        end
      end
    end
  end
end
