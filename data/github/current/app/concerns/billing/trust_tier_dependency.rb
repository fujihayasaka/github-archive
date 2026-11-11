# typed: strict
# frozen_string_literal: true

module Billing
  module TrustTierDependency
    extend ActiveSupport::Concern
    extend T::Helpers

    sig { params(entity: T.any(User, Organization, Business)).returns(T::Boolean) }
    def show_trust_tier_banner?(entity)
      return false unless entity.feature_flag_enabled?(:billing_can_proceed_with_usage_trust_tier, default: true)
      return false if entity.customer.nil?

      # Calculate the trust tier for the entity
      trust_tier = ::TrustTiers::Tier.for_billable_owner(entity).tier
      # add a 2 second timeout since this is a blocking call and we don't want to
      # have runaway CPWU requests cause unicorns when loading the banner
      billing_platform_client = Billing::Platform::Api::Client.new(timeout: 2)
      cpwu_response = billing_platform_client.can_proceed_with_usage(
        usage_key: {
          ## The SKU is unrelated to :TrustTierUsageLimitReached response cases but is needed due to CPWU API requiring it
          ## for 100% Discounts currently. This is a small and inconsequential workaround, but should be cleaned up as a part of
          ## https://github.com/github/gitcoin/issues/21091
          sku: "actions_linux_64_core",
          product: "actions",
          entityDetail: {
            customerId: entity.customer&.id.to_s,
          },
        },
        trust_tier: trust_tier
      )

      if cpwu_response.is_a?(Billing::Platform::Api::Error)
        GitHub.dogstats.increment("billing.trust_tier_banner.error")
        return false
      end

      !cpwu_response[:can_proceed] && cpwu_response[:status] == :TrustTierUsageLimitReached
    end
  end
end
