# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class FundingLink < Platform::Objects::Base
      description "A funding platform link for a repository."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        repo = object.repository

        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(
            :get_funding,
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
        permission.typed_can_see?("Repository", object.repository)
      end

      minimum_accepted_scopes ["public_repo"]

      field :platform, Enums::FundingPlatform,
        description: "The funding platform this link is for.",
        null: false

      field :url, Scalars::URI,
        description: "The configured URL for this funding link.",
        null: false
    end
  end
end
