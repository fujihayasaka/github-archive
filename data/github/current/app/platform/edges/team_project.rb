# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class TeamProject < Edges::Base
      description "Represents a connection between a team (parent) and a project (child)."
      visibility :internal

      minimum_accepted_scopes ["read:org"]

      node_type Objects::Project

      url_fields prefix: "team_project", description: "The HTTP URL for this team's project" do |edge|
        project = edge.node
        team = edge.parent

        team.async_organization.then do |org|
          template = Addressable::Template.new("/orgs/{org}/teams/{team}/projects/{project}")
          template.expand org: org.display_login, team: team.slug, project: project.id
        end
      end

      field :permission, Enums::ProjectPermission, description: "The permission level the team has on the project", null: false

      field :inherited_permission_origin, Objects::Team, description: "The parent team that grants inherited permission to this project", null: true

      def inherited_permission_origin
        project = @object.node
        team = @object.parent
        return unless team.ancestor_ids.present?

        Loaders::MostCapableInheritedTeamProjectAbilities.load(team: team, project: project).then do |ability|
          ability && Loaders::ActiveRecord.load(Team, ability.actor_id)
        end
      end

      field :inherited_permission, Enums::ProjectPermission, description: "The inherited permission level the team has on the project", null: true

      def inherited_permission
        project = @object.node
        team = @object.parent
        return unless team.ancestor_ids.present?

        Loaders::MostCapableInheritedTeamProjectAbilities.load(team: team, project: project).then do |ability|
          ability && ability.action.to_s
        end
      end
    end
  end
end
