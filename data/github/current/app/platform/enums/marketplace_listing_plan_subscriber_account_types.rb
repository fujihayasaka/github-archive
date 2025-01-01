# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MarketplaceListingPlanSubscriberAccountTypes < Platform::Enums::Base
      description "The possible types of accounts that could be allowed to subscribe to a Marketplace listing plan."
      visibility :internal

      value "USERS_AND_ORGANIZATIONS", "Personal accounts and organizations can subscribe to the plan.", value: "users_and_organizations"
      value "USERS_ONLY", "Only personal accounts can subscribe to the plan.", value: "users_only"
      value "ORGANIZATIONS_ONLY", "Only organizations can subscribe to the plan.", value: "organizations_only"
    end
  end
end
