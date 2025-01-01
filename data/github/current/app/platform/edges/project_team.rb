# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class ProjectTeam < Edges::Base
      description "Represents a connection between a project (parent) and a team (child)."
      visibility :internal

      minimum_accepted_scopes ["read:org"]

      node_type Objects::Team

      url_fields prefix: "project_team", description: "The HTTP URL for this project's team" do |edge|
        team = edge.node
        project = edge.parent
        project.async_owner.then do |owner|
          template = Addressable::Template.new("/orgs/{owner}/projects/{project}/settings/teams/{team}")
          template.expand owner: owner.display_login, project: project.number, team: team.id
        end
      end

      field :permission, Enums::ProjectPermission, description: "The permission level the team has on the project", null: false
    end
  end
end
