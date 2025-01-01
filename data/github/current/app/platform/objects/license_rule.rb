# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class LicenseRule < Platform::Objects::Base
      description "Describes a License's conditions, permissions, and limitations"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        # It's not a license, but for the sake of DRY,
        # route to the same check for :public_site_information
        permission.typed_can_access?("License", object)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :key, String, "The machine-readable rule key", method: :tag, null: false
      field :label, String, "The human-readable rule label", null: false
      field :description, String, "A description of the rule", null: false
    end
  end
end
