# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class UserDashboardNavLink < Platform::Objects::Base
      description "A user dashboard top level navigation link."
      scopeless_tokens_as_minimum
      required_capabilities [:mobile_only_schema_mask]

      # UserDashboardNavLink objects cannot be accessed directly and are only materialized
      # via the parent UserDashboard object, which retrieves them from a static list of links
      # defined in the Mobile::HomeNavLink::ALL_LINKS constant. Materialization in the
      # parent object simply sorts and/or hides the links based on user preferences which are
      # retrieved from the KV store. Since the parent object is already authorized and there is no
      # user-entered data in the link objects, we should be fine skipping authorization checks here.
      # If any of these assumptions change, we should revisit this decision.
      def self.async_api_can_access?(permission, _)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # UserDashboardNavLink objects cannot be accessed directly and are only materialized
      # via the parent UserDashboard object, which retrieves them from a static list of links
      # defined in the Mobile::HomeNavLink::ALL_LINKS constant. Materialization in the
      # parent object simply sorts and/or hides the links based on user preferences which are
      # retrieved from the KV store. Since the parent object is already authorized and there is no
      # user-entered data in the link objects, we should be fine skipping authorization checks here.
      # If any of these assumptions change, we should revisit this decision.
      def self.async_viewer_can_see?(permission, _)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      field :identifier, Enums::UserDashboardNavLinkIdentifier, "Link identifier value", null: false
      field :hidden, Boolean, "Whether this link is hidden or not on the dashboard", null: false
    end
  end
end
