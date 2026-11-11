# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class LinkProjectV2ToTeam < Platform::Mutations::Base
      description "Links a project to a team."

      minimum_accepted_scopes ["read:org",  "project"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :project_id, ID, "The ID of the project to link to the team.", required: true, loads: Objects::ProjectV2

      argument :team_id, ID, "The ID of the team to link to the project.", required: true, loads: Objects::Team

      field :team, Objects::Team, "The team the project is linked to", null: true

      def self.async_api_can_modify?(permission, project:, team:)
        Platform::Helpers::ProjectV2.async_api_can_modify_team_project_link?(
          permission,
          project: project,
          team: team
        )
      end

      def resolve(project:, team:)
        Platform::Helpers::ProjectV2.validate_update_team_project_link(
          context[:viewer],
          project,
          team
        )
        begin
          project.grant_role(team, "project_reader")
          { team: team }
        rescue Permissions::Granters::RoleGranter::GrantFailure
          raise Errors::Unprocessable.new("Could not link the team to the project. Please try again later.")
        end
      end
    end
  end
end
