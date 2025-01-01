# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class UserDashboardNavLink < Platform::Objects::Base
      description "A user dashboard top level navigation link."
      scopeless_tokens_as_minimum
      mobile_only true

      def self.async_api_can_access?(permission, _)
        # Simple object authorization.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      def self.async_viewer_can_see?(permission, _)
        # Simple object authorization.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      field :identifier, Enums::UserDashboardNavLinkIdentifier, "Link identifier value", null: false
      field :hidden, Boolean, "Whether this link is hidden or not on the dashboard", null: false
    end
  end
end
