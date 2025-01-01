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
        "Max" => 5000
      }
    end
  end
end
