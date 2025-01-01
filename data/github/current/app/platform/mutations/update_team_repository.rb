# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateTeamRepository < Platform::Mutations::Base
      description "Update team repository. Additionally requires organization write permission."
      visibility :internal

      minimum_accepted_scopes ["write:org"]

      argument :repository_id, ID, "The ID of the repository to update.", required: true, loads: Objects::Repository, as: :repo
      argument :team_id, ID, "The ID of the team of the repository.", required: true, loads: Objects::Team
      argument :permission, String, "The permission the team has on the repository.", required: true

      field :repository, Objects::Repository, "The repository that was updated.", null: true
      field :team, Objects::Team, "The team of the repository.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, team:, **inputs)
        team.async_organization.then do |organization|
          if organization && organization.feature_enabled?(:teams_cap_updates)
            # allow repo admins to add the repository to a team they do not maintain but can view
            repo = inputs[:repo]
            if repo && organization == repo.organization && repo.resources.administration.writable_by?(permission.viewer)
              return true if team.visible_to?(permission.viewer)
            end

            permission.access_allowed?(:v4_manage_team, resource: team, team: team, organization: organization, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: false)
          else
            permission.access_allowed?(:v4_manage_team, resource: team, organization: organization, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: false)
          end
        end
      end

      def resolve(team:, repo:, **inputs)
        permission = inputs[:permission]

        unless repo.resources.administration.writable_by?(context[:viewer])
          raise Errors::Forbidden.new("You must have administrative rights on this repository.")
        end

        result = team.add_or_update_repository(repo, permission)

        if result.error?
          raise Errors::Unprocessable.new(result.message)
        end

        {
          repository: repo,
          team: team,
        }
      end
    end
  end
end
