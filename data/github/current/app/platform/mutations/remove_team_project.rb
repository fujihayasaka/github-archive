# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveTeamProject < Platform::Mutations::Base
      description "Removes the team from the project."
      visibility :internal

      minimum_accepted_scopes ["read:org"]

      argument :project_id, ID, "The ID of the project to remove.", required: true, loads: Objects::Project
      argument :team_id, ID, "The ID of the team to remove the project from.", required: true, loads: Objects::Team

      field :project, Objects::Project, "The project that was removed.", null: true
      field :team, Objects::Team, "The team that the project was removed from.", null: true

      def resolve(team:, project:, **inputs)
        if project.owner_type == "Repository"
          raise Errors::Unprocessable.new("Teams cannot have repository projects.")
        end

        # The viewer must be able to administer either the project or the team
        # in order to break the connection.
        if !project.adminable_by?(context[:viewer]) && !team.adminable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to remove this project from this team.")
        end

        if team.remove_project(project)
          { project: project, team: team }
        else
          raise Errors::Unprocessable.new("Could not remove project #{project.global_relay_id} from team #{team.global_relay_id}.")
        end
      end
    end
  end
end
