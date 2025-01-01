# typed: strict
# frozen_string_literal: true

module SponsorsListing::CustomTierDependency
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  requires_ancestor { SponsorsListing }

  CUSTOM_AMOUNT_SETTINGS_REMOVAL_DATE = "2022-10-03"

  included do
    T.bind(self, T.class_of(SponsorsListing))

    validate :custom_tier_amount_settings_in_cents_divisible_by_100
    validate :custom_tier_amount_settings_in_cents_within_limit
    validate :suggested_custom_tier_amount_in_cents_at_least_min_amount
  end

  # Public: Get the dollar amount that should be suggested to sponsors when custom tiers are
  # allowed for this Sponsors listing.
  sig { returns T.nilable(BigDecimal) }
  def suggested_custom_tier_amount_in_dollars
    amount = suggested_custom_tier_amount_in_cents
    return unless amount
    amount.abs / BigDecimal(100)
  end

  # Public: Set the amount to suggest to sponsors when creating a custom sponsorship.
  #
  # raw_dollar_value - numeric String or number representing the dollars to suggest
  sig { params(raw_dollar_value: T.any(String, Numeric)).void }
  def suggested_custom_tier_amount_in_dollars=(raw_dollar_value)
    dollar_amount = raw_dollar_value.to_i.abs
    self.suggested_custom_tier_amount_in_cents = if dollar_amount.nonzero?
      dollar_amount * 100
    end
  end

  # Public: Get the minimum dollar amount when custom tiers are allowed for this Sponsors listing.
  sig { returns T.nilable(BigDecimal) }
  def min_custom_tier_amount_in_dollars
    min_amount = min_custom_tier_amount_in_cents
    return unless min_amount
    min_amount.abs / BigDecimal(100)
  end

  # Public: Set the minimum amount for creating a custom sponsorship.
  #
  # raw_dollar_value - numeric String or number representing the minimum dollar amount
  sig { params(raw_dollar_value: T.any(String, Numeric)).void }
  def min_custom_tier_amount_in_dollars=(raw_dollar_value)
    dollar_amount = raw_dollar_value.to_i.abs
    self.min_custom_tier_amount_in_cents = if dollar_amount.nonzero?
      dollar_amount * 100
    end
  end

  # Public: Get this listing's custom tiers that are in use by active sponsorships,
  # one for each price point.
  #
  # Returns an ActiveRecord::Relation for SponsorsTier.
  sig { returns ActiveRecord::Relation }
  def unique_custom_tiers
    tier_ids = Sponsorship.active
      .joins(:tier)
      .merge(SponsorsTier.with_custom_state.for_listing(id))
      .group("sponsors_tiers.monthly_price_in_cents")
      .order("sponsors_tiers.id")
      .pluck("sponsors_tiers.id")
    sponsors_tiers.where(id: tier_ids).order(:monthly_price_in_cents)
  end

  sig { params(old_amount: T.nilable(Integer), actor: User).void }
  def instrument_custom_amount_settings_change(old_amount, actor:)
    same_amount_value = suggested_custom_tier_amount_in_cents == old_amount
    return if same_amount_value

    # Audit log
    instrument(:custom_amount_settings_change,
      old_setting: true,
      new_setting: true,
      old_suggested_amount_in_cents: old_amount,
      new_suggested_amount_in_cents: suggested_custom_tier_amount_in_cents,
      actor: actor,
      prefix: :sponsors)

    # Hydro
    GlobalInstrumenter.instrument("sponsors.custom_amount_settings_change", actor: actor,
      listing: self)
  end

  private

  sig { returns T::Hash[Symbol, T.nilable(Integer)] }
  def custom_tier_amount_setting_values
    {
      suggested_custom_tier_amount_in_cents: suggested_custom_tier_amount_in_cents,
      min_custom_tier_amount_in_cents: min_custom_tier_amount_in_cents,
    }
  end

  sig { void }
  def custom_tier_amount_settings_in_cents_divisible_by_100
    custom_tier_amount_setting_values.each do |setting, setting_value|
      next unless setting_value

      if setting_value % 100 != 0
        errors.add(setting, "must be divisible by 100")
      end
    end
  end

  sig { void }
  def custom_tier_amount_settings_in_cents_within_limit
    custom_tier_amount_setting_values.each do |setting, setting_value|
      next unless setting_value

      if setting_value > SponsorsTier::MAX_SPONSORSHIP_AMOUNT_IN_CENTS
        errors.add(setting, "exceeds maximum tier amount of #{SponsorsTier::MAX_SPONSORSHIP_AMOUNT_HUMAN}")
      end
    end
  end

  sig { void }
  def suggested_custom_tier_amount_in_cents_at_least_min_amount
    suggested_amount = suggested_custom_tier_amount_in_cents
    min_amount = min_custom_tier_amount_in_cents
    return unless suggested_amount&.nonzero? && min_amount&.nonzero?

    if suggested_amount < min_amount
      errors.add(:suggested_custom_tier_amount_in_cents, "must be at least the minimum amount for custom sponsorships")
      errors.add(:min_custom_tier_amount_in_cents, "must be no more than the suggested amount for custom sponsorships")
    end
  end
end
