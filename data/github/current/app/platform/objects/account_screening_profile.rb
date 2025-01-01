# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class AccountScreeningProfile < Platform::Objects::Base
      description "A user's or organization's account screening profile."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      visibility :internal
      minimum_accepted_scopes ["site_admin"]
      field :id, ID, description: "Account's ID", null: false
      field :msft_trade_screening_status, String, description: "Account's SDN screening status", null: false
      field :last_trade_screen_date, Scalars::DateTime, description: "Date and time when the account's screening status was last updated", null: true
      field :external_uuid, String, description: "Account's external id used for identifying the account", null: true
    end
  end
end
