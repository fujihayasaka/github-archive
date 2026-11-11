# typed: true
# frozen_string_literal: true

class Stafftools::TrustTiers::TieringComponent < ApplicationComponent
  attr_reader :user, :tier_details, :forced_tier, :tier_result, :codespaces_config,
              :calculated_tier_result, :verbose_tier_reason, :verbose_calculated_tier_reason,
              :spending_limit_text

  def initialize(user)
    @user = user
    @tier_details = TrustTiers::TierDetails.new(user)
    @forced_tier  = user.settings.get(:trust_tier)

    # tiering now returns TierResult object
    @tier_result = TrustTiers::Tier.for_billable_owner(user)
    @forced_tier = -1 if @tier_result.reason == TrustTiers::TierResult::BUSINESS_OR_INVOICED
    @codespaces_config = Codespaces::Tier.config_for_tier(@tier_result, user)

    @calculated_tier_result = TrustTiers::Tier.for_billable_owner(user, force_calculation: true)
    spending_limit = Billing::BudgetLimit::FindBudget.by_tier(@tier_result.tier)

    if spending_limit == Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT
      @spending_limit_text = "Unlimited"
    else
      @spending_limit_text = Billing::Money.new(spending_limit).format
    end

    # load verbose reason for tiering
    @verbose_tier_reason            = @tier_result.verbose_reason
    @verbose_calculated_tier_reason = @calculated_tier_result.verbose_reason
  end

  def business_or_invoiced
    @user.is_a?(Business) || @user.invoiced?
  end
end
