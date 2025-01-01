# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddTeamProject < Platform::Mutations::Base
      description "Adds project to team."
      visibility :internal

      minimum_accepted_scopes ["read:org"]

      argument :project_id, ID, "The ID of the project to add to the team.", required: true, loads: Objects::Project
      argument :team_id, ID, "The ID of the team to add the project to.", required: true, loads: Objects::Team
      argument :permission, Enums::ProjectPermission, "The permission that the team should have on the project.", required: false, default_value: "read"

      field :project_team_edge, Edges::ProjectTeam, "The edge between the project and the team.", null: true

      def resolve(team:, project:, **inputs)

        unless project.adminable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to change collaboration settings for this project.")
        end

        unless team.visible_to?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to view the specified team.")
        end

        # String#to_sym is safe to call here, since we know it's going to be
        # one of the few values in Enum::ProjectPermission.
        status = team.add_project(project, inputs[:permission].to_sym)

        if status.success?
          scope = project.direct_teams.order("name ASC")
          connection = Platform::ConnectionWrappers::Relation.new(scope,  parent: project, context: context)

          { project_team_edge: Platform::Models::ProjectTeamEdge.new(team, connection) }
        else
          error = case status
          when Team::ModifyProjectStatus::NO_PERMISSION
            "A valid permission must be provided."
          when Team::ModifyProjectStatus::NON_ORGANIZATION_PROJECT
            "Only organization-owned projects can be added to teams."
          when Team::ModifyProjectStatus::NOT_OWNED
            "A project cannot be added to a team in a different organization."
          when Team::ModifyProjectStatus::DUPE
            "This project is already on this team."
          else
            "Could not add project #{project.id} to team #{team.id}."
          end

          raise Errors::Unprocessable.new(error)
        end
      end
    end
  end
end
