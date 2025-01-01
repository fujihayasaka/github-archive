# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PermissionSource < Platform::Objects::Base
      description "A level of permission and source for a user's access to a repository."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        org = object["organization"]
        repo = object["repo"]

        permission.access_allowed?(
          :read_member_repo_permissions,
          resource: org,
          current_repo: repo,
          current_org: org,
          allow_integrations: true,
          allow_user_via_granular_actor: true
        )
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        viewer = permission.viewer
        return true if viewer && viewer.site_admin?
        org = object["organization"]
        org.resources.organization_administration.async_readable_by?(viewer)
      end

      minimum_accepted_scopes ["admin:org"]
      visibility :public

      field :permission, Platform::Enums::DefaultRepositoryPermissionField, description: "The level of access this source has granted to the user.", null: false
      field :roleName, String, description: "The name of the role this source has granted to the user.", null: true
      field :source, Unions::PermissionGranter, description: "The source of this permission.", null: false

      field :organization, Objects::Organization, description: "The organization the repository belongs to.", null: false
    end
  end
end
