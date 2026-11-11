# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ReusedCardFingerprint < Platform::Objects::Base
      description "Reused payment fingerprints (cards and PayPal) in the last 30 days"

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      field :card_fingerprint, String, description: "The card fingerprint", null: false
      field :count, Integer, description: "The number of times the card fingerprint was reused in the last 30 days", null: false

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end
    end
  end
end
