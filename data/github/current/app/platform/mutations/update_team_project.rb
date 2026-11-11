# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateTeamProject < Platform::Mutations::Base
      description "Updates team's permission on project."
      visibility :internal

      minimum_accepted_scopes ["read:org"]

      argument :project_id, ID, "The ID of the project that's on the team.", required: true, loads: Objects::Project
      argument :team_id, ID, "The ID of the team that the project is on.", required: true, loads: Objects::Team
      argument :permission, Enums::ProjectPermission, "The permission that the team should have on the project.", required: true

      field :project, Objects::Project, "The project that is on the team.", null: true
      field :team, Objects::Team, "The team that the project is on.", null: true

      def resolve(team:, project:, **inputs)
        raise Errors::Unprocessable.new("A permission must be specified") if inputs[:permission] == "none"

        unless project.adminable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to change collaboration settings for this project.")
        end

        unless team.visible_to?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to view the specified team.")
        end

        # String#to_sym is safe to call here, since we know it's going to be
        # one of the few values in Enum::ProjectPermission.
        if team.update_project_permission(project, inputs[:permission].to_sym)
          { project: project, team: team }
        else
          raise Errors::Unprocessable.new("Could not update team #{team.global_relay_id}'s permission on project #{project.global_relay_id}.")
        end
      end
    end
  end
end
