# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class BlockPaymentMethodResult < Platform::Objects::Base
      docs_category :billing
      description "The per-fingerprint result of a blockPaymentMethods mutation"

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      field :card_fingerprint, String, description: "The card fingerprint that was processed", null: false
      field :blocked, Boolean, description: "Whether the payment method was successfully blocked", null: false
      field :error, String, description: "The error message if the payment method could not be blocked", null: true

      # Determine whether the viewer can access this object via the API (called internally).
      def self.async_api_can_access?(permission, _object)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      def self.async_viewer_can_see?(permission, object)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end
    end
  end
end
