# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateTeamsRepository < Platform::Mutations::Base
      MAX_TEAMS = 10
      description "Update team repository."

      minimum_accepted_scopes ["write:org", "repo"]

      argument :repository_id, ID, "Repository ID being granted access to.", required: true, loads: Objects::Repository, as: :repo
      argument :team_ids, [ID], "A list of teams being granted access. Limit: #{MAX_TEAMS}", required: true, loads: Objects::Team
      argument :permission, Enums::RepositoryPermission, "Permission that should be granted to the teams.", required: true

      field :repository, Objects::Repository, "The repository that was updated.", null: true
      field :teams, [Objects::Team], "The teams granted permission on the repository.", null: true

      # Determine whether the viewer can access this mutation via the API.
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, teams:, **inputs)
        promises = teams.map do |team|
          team.async_organization.then do |organization|
            if organization && organization.feature_enabled?(:teams_cap_updates)
              # allow repo admins to add the repository to a team they do not maintain but can view
              repo = inputs[:repo]
              if repo && organization == repo.organization && repo.resources.administration.writable_by?(permission.viewer)
                next true if team.visible_to?(permission.viewer)
              end
            end

            permission.access_allowed?(:v4_manage_team, resource: team, team: team, organization: organization, current_repo: nil, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
        promises.map(&:value).all?
      end

      def resolve(teams:, repo:, **inputs)
        unless repo && repo.resources.administration.writable_by?(context[:viewer])
          raise Errors::Forbidden.new("You must have administrative rights on this repository.")
        end

        if teams.size > MAX_TEAMS
          raise Errors::Unprocessable.new("Request exceeded limit of #{MAX_TEAMS} teams.")
        end

        Team.transaction do
          teams.each do |team|
            result = team.add_or_update_repository(
              repo,
              Team::ABILITIES_TO_PERMISSIONS[inputs[:permission].to_sym],
            )

            if result.error?
              raise Errors::Unprocessable.new("Could not add repository to team. Reason: #{result.status}")
            end
          end
        end

        {
          repository: repo,
          teams: teams,
        }
      end
    end
  end
end
