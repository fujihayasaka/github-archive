# typed: true
# frozen_string_literal: true

require "scientist"

class Billing::BudgetLimit::FindBudget
  extend Scientist

  TRUSTED_TIER_SPENDING_LIMIT = BigDecimal("Infinity")
  NEUTRAL_TIER_SPENDING_LIMIT = BigDecimal(1000 * 100) # $1000 spending limit
  UNTRUSTED_TIER_SPENDING_LIMIT = BigDecimal(1000 * 100) # $1000 spending limit

  def self.for_account(account, shared)
    tier = load_tier(account, shared)

    tier_to_spending_limit(tier)
  end

  def self.by_tier(tier)
    tier_to_spending_limit(tier)
  end

  class << self
    private

    # moved this to a function for easy reuse.
    def tier_to_spending_limit(tier)
      case tier
      when TrustTiers::Tier::TRUSTED
        TRUSTED_TIER_SPENDING_LIMIT
      when TrustTiers::Tier::NEUTRAL
        NEUTRAL_TIER_SPENDING_LIMIT
      else # TrustTiers::Tier::UNTRUSTED
        UNTRUSTED_TIER_SPENDING_LIMIT
      end
    end

    def load_tier(account, shared)
      TrustTiers::Tier.for_billable_owner(account).tier
    end
  end
end
