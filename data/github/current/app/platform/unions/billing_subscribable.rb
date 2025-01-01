# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class BillingSubscribable < Platform::Unions::Base
      description "[DEPRECATING] Objects that a user can subscribe to and be billed for."
      visibility :internal
      feature_flag :billing_subscribable_usage_deprecation

      possible_types(
        Objects::MarketplaceListingPlan,
        Objects::SponsorsTier,
      )
    end
  end
end
