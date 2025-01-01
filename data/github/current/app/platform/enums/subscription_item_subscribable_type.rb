# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SubscriptionItemSubscribableType < Platform::Enums::Base
      description "The possible states of a Sponsors tier."
      visibility :under_development

      value "MARKETPLACE_LISTING_PLAN", "Subscription is for a Marketplace listing", value: 0
      value "SPONSORS_TIER", "Subscription is for a Sponsors listing", value: 1
    end
  end
end
