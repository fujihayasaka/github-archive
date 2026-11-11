
# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class UserEmailMetadata < Platform::Objects::Base
      description "Email attributes from External Identity"


      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        # This object is only accessible from an `ExternalIdentitiesScimAttributes` or `ExternalIdentitiesSamlAttributes` object,
        # which has its own authorization. So we don't need to re-authorize this.
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      minimum_accepted_scopes ["read:org", "read:enterprise"]

      field :primary, Boolean, "Boolean to identify primary emails", null: true
      def primary
        @object["metadata"]["primary"]
      end

      field :type, String, "Type of email", null: true

      def type
        @object["metadata"]["type"]
      end

      field :value, String, "Email id", null: false
      def value
        @object["value"]
      end
    end
  end
end
