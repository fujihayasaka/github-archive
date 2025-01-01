# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveTeamMember < Platform::Mutations::Base
      description "Removes member from team."
      visibility :internal

      minimum_accepted_scopes ["write:org"]

      argument :user_id, ID, "The ID of the team member to remove.", required: true, loads: Objects::User
      argument :team_id, ID, "The ID of the team to remove the team member from.", required: true, loads: Objects::Team

      field :user, Objects::User, "The user that was removed as a team member.", null: true
      field :team, Objects::Team, "The team that the member was removed from.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, team:, **inputs)
        team.async_organization.then do |organization|
          permission.access_allowed?(:v4_manage_team, team: team, resource: team, organization: organization, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: false)
        end
      end

      def resolve(team:, user:, **inputs)

        unless team.adminable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to remove members from this team.")
        end

        if team.remove_member(user)
          {
            user: user,
            team: team,
          }
        else
          raise Errors::Unprocessable.new("User is not a member of this team.")
        end
      end
    end
  end
end
