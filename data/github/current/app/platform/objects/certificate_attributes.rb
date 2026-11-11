# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CertificateAttributes < Platform::Objects::Base
      description "Name attributes from an X.509 certificate."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # This is only called internally as a field in the SmimeSignature object
        # and visibility is pre-checked on the SmimeSignature object itself.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      visibility :internal

      minimum_accepted_scopes ["repo"]

      field :common_name, String, description: "CN attribute", null: true

      def common_name
        @object["CN"]&.force_encoding("UTF-8")
      end

      field :email_address, String, description: "emailAddress attribute", null: true

      def email_address
        @object["emailAddress"]&.force_encoding("UTF-8")
      end

      field :organization, String, description: "O attribute", null: true

      def organization
        @object["O"]&.force_encoding("UTF-8")
      end

      field :organization_unit, String, description: "OU attributes", null: true

      def organization_unit
        @object["OU"]&.force_encoding("UTF-8")
      end
    end
  end
end
