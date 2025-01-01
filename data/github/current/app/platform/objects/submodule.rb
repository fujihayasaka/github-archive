# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Submodule < Platform::Objects::Base
      include GitHub::UTF8

      description "A pointer to a repository at a specific revision embedded inside another repository."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, submodule)
        permission.typed_can_access?("Repository", submodule.superproject_repository)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, submodule)
        submodule.superproject_repository.async_visible_and_readable_by?(permission.viewer)
      end

      scopeless_tokens_as_minimum

      field :subproject_commit_oid, Scalars::GitObjectID, description: "The commit revision of the subproject repository being tracked by the submodule", method: :async_subproject_commit_oid, null: true

      field :name, String, description: "The name of the submodule in .gitmodules", null: false
      def name
        utf8(@object.name&.dup)
      end

      field :name_raw, Platform::Scalars::Base64String, description: "The name of the submodule in .gitmodules (Base64-encoded)", null: false, method: :name

      field :path, String, description: "The path in the superproject that this submodule is located in", null: false
      def path
        utf8(@object.path&.dup)
      end

      field :path_raw, Platform::Scalars::Base64String, description: "The path in the superproject that this submodule is located in (Base64-encoded)", null: false, method: :path

      field :git_url, Scalars::URI, description: "The git URL of the submodule repository", null: false

      field :branch, String, description: "The branch of the upstream submodule for tracking updates", null: true
    end
  end
end
