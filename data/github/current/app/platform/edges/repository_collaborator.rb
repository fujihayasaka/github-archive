# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class RepositoryCollaborator < Edges::Base
      description "Represents a user who is a collaborator of a repository."

      minimum_accepted_scopes ["public_repo"]

      field :node, Objects::User, null: false

      field :permission, Enums::RepositoryPermission, description: "The permission the user has on the repository.", null: false

      def permission
        user = @object.node
        repository = @object.parent

        repository.async_action_or_role_level_for(user, include_custom_roles: false).then do |permission|
          permission.to_s
        end
      end

      field :permission_sources, [Objects::PermissionSource], minimum_accepted_scopes: ["admin:org"], visibility: :public, description: "A list of sources for the user's access to the repository.", null: true

      def permission_sources
        repository = @object.parent
        user = @object.node
        repository.async_owner.then do |owner|
          repository.async_permission_sources(user, context[:viewer]).then do |grants|
            grants.each { |g| g["organization"] = owner }
          end
        end
      end
    end
  end
end
