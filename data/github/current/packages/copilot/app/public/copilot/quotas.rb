# typed: strict
# frozen_string_literal: true

module Copilot
  class Quotas
    # This returns the current quotas for all features
    # This is the free allotment for all users, not the individual user's quota
    sig { returns(T::Hash[String, Integer]) }
    def self.monthly_quotas
      # well now you're back to being dynamic
      Copilot::LimitedUser.monthly_quota_limits
    end

    # this is hardcoded and is bad
    # but I dont know where this config is stored today
    # so maybe hardcoding right now is fine for testing
    sig { returns(T::Hash[String, Integer]) }
    def self.premium_interactions_monthly_quotas
      {
        "Business" => 300,
        "Enterprise" => 1000,
        "Pro & Complimentary" => 300,
        "Pro+" => 1500,
        "Max" => 5000,
        "Educational" => 300
      }
    end

    # There is no canonical way to look up included AI usage for a SKU other than
    # the user's current one (`CopilotLimiter::Twirp.quota_client.get_quota_remaining`
    # only returns the entitlement for the caller's active access type).
    # This is a workaround until we have a better way to look this up
    # (e.g. via CopilotLimiter's GetEntitlementsForSKU).
    CFI_INCLUDED_AIC = T.let({
      # Educational users receive a complimentary $2 (200 cents) AI usage entitlement.
      educational: 200,
      pro: 1_500,
      pro_plus: 7_000,
      max: 20_000,
    }.freeze, T::Hash[Symbol, Integer])
  end
end
