# typed: true
# frozen_string_literal: true
class Stafftools::TrustTiers::TieringSelectComponent < ApplicationComponent
  attr_reader :user, :possible_forced_tiers, :billable_owner_tier, :forced_tier, :business_or_invoiced

  def initialize(user, billable_owner_tier, calculated_owner_tier, forced_tier, business_or_invoiced)
    @user = user
    @business_or_invoiced = business_or_invoiced

    # tiering now returns an two element array, the first element is the tier
    @billable_owner_tier   = billable_owner_tier
    @calculated_owner_tier = calculated_owner_tier
    @forced_tier           = forced_tier

    @possible_forced_tiers = UserSettings::TRUST_TIERS.drop(1).inject([]) do |acc, tier|
      ### if we have forced a tier, we need to behave a little differently
      if @forced_tier > 0
        # if the current tier in the iteration is our original calculated tier, we need to allow them to revert to it
        # if the current tier in the iteration is NOT the forced tier, we add it to the list
        if tier == calculated_owner_tier
          acc << [-1, "Revert To Calculated Tier: #{TrustTiers::Tier.tier_name(@calculated_owner_tier)}"]
        else
          acc << [tier, "Force Tier: #{TrustTiers::Tier.tier_name(tier)}"] unless tier == forced_tier
        end
      else
        # if we aren't in forced mode, we just add it normally
        acc << [tier, "Force Tier: #{TrustTiers::Tier.tier_name(tier)}"] unless tier == calculated_owner_tier
      end
      acc
    end
  end
end
