# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SecurityAdvisoryReference < Platform::Objects::Base
      visibility :public

      description "A GitHub Security Advisory Reference"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # Access to this object is managed by its parent SecurityAdvisory.
        # _object is a hash so checking permissions on the parent is not possible.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # Access to this object is managed by its parent SecurityAdvisory.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum


      field :url, Scalars::URI, "A publicly accessible reference", null: false
    end
  end
end
