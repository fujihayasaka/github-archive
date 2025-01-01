# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SpokenLanguage < Platform::Objects::Base
      description "Represents a spoken language."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, language)
        permission.access_allowed?(:public_site_information, resource: Platform::PublicResource.new, current_repo: nil, # rubocop:disable GitHub/PublicResource
          current_org: nil, allow_integrations: true, allow_user_via_granular_actor: true)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :name, String, "The name of the current spoken language, e.g., \"Spanish\".", null: false
      field :code, String, "A two-character code representing the current spoken language, e.g., \"es\".", null: false
    end
  end
end
