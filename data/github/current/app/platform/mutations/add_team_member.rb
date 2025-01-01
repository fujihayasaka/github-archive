# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddTeamMember < Platform::Mutations::Base
      description "Adds member to team."
      visibility :internal

      minimum_accepted_scopes ["write:org"]

      argument :user_id, ID, "The ID of the team member to add.", required: true, loads: Objects::User
      argument :team_id, ID, "The ID of the team to add to the team.", required: true, loads: Objects::Team

      field :user, Objects::User, "The user that was added as a team member.", null: true
      field :team, Objects::Team, "The team that the member was added to.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, team:, **inputs)
        team.async_organization.then do |organization|
          current_org = organization
          permission.access_allowed?(:v4_manage_team, team: team, organization: current_org, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: false)
        end
      end

      def resolve(team:, user:, **inputs)

        if !team.user_can_add_member?(user, actor: context[:viewer])
          raise Errors::Forbidden.new("Viewer does not have permission to add members to this team.")
        end

        team.add_member(user, adder: context[:viewer])
        {
          user: user,
          team: team,
        }
      end
    end
  end
end
