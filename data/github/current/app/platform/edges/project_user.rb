# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class ProjectUser < Edges::Base
      description "Represents a user project."
      visibility :internal

      minimum_accepted_scopes ["read:org"]

      node_type Objects::User

      url_fields prefix: "project_user", description: "The HTTP URL for this project's user", visibility: :internal do |edge|
        user = edge.node
        project = edge.parent
        project.async_owner.then do |owner|
          template = Addressable::Template.new("/orgs/{owner}/projects/{project}/settings/users/{user}")
          template.expand owner: owner.display_login, project: project.number, user: user.id
        end
      end

      field :permission, Enums::ProjectPermission, description: "The permission level the user has on the project", null: false
    end
  end
end
