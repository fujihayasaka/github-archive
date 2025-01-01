# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryContactLink < Platform::Objects::Base
      description "A repository contact link."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        permission.async_repo_and_org_owner(object).then do |repo, org|
          permission.access_allowed?(
            :list_repo_contact_links,
            resource: repo,
            current_repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end


      minimum_accepted_scopes ["repo"]

      field :name, String, "The contact link name.", null: false
      field :about, String, "The contact link purpose.", null: false
      field :url, Scalars::URI, "The contact link URL.", null: false
    end
  end
end
