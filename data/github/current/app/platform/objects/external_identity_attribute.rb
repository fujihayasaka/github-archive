# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ExternalIdentityAttribute < Platform::Objects::Base
      description "An attribute for the External Identity attributes collection"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, saml_attributes)
        permission.typed_can_access?("ExternalIdentity", saml_attributes.identity)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("ExternalIdentity", object.identity)
      end

      minimum_accepted_scopes ["read:org", "read:enterprise"]

      field :name, String, description: "The attribute name", null: false

      def name
        @object.attribute["name"]
      end

      field :value, String, description: "The attribute value", null: false
      def value
        @object.attribute["value"]
      end

      field :metadata, String, description: "The attribute metadata as JSON", null: true
      def metadata
        metadata = @object.attribute["metadata"]
        return if @object.attribute["metadata"].empty?
        metadata.to_json
      end
    end
  end
end
