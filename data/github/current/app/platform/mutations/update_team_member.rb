# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateTeamMember < Platform::Mutations::Base
      description "Update team member."
      visibility :internal

      minimum_accepted_scopes ["write:org"]

      argument :user_id, ID, "The ID of the team member to update.", required: true, loads: Objects::User
      argument :team_id, ID, "The ID of the team of the member.", required: true, loads: Objects::Team
      argument :role, Enums::TeamMemberRole, "The role of the team member.", required: false

      field :user, Objects::User, "The team member that was updated.", null: true
      field :team, Objects::Team, "The team of the member.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, team:, **inputs)
        team.async_organization.then do |organization|
          if organization && organization.feature_enabled?(:teams_cap_updates)
            permission.access_allowed?(:v4_manage_team, team: team, resource: team, organization: organization, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: false)
          else
            permission.access_allowed?(:v4_manage_team, resource: team, organization: organization, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: false)
          end
        end
      end

      def resolve(team:, user:, **inputs)

        unless team.adminable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to update members on this team.")
        end

        case inputs[:role]
        when "maintainer"
          team.promote_maintainer(user)
        when "member"
          team.demote_maintainer(user)
        end

        {
          user: user,
          team: team,
        }
      end
    end
  end
end
