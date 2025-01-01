# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Tiers::CustomAmountSettingsComponent < ApplicationComponent
  def initialize(sponsors_listing:, frequency:)
    @sponsors_listing = sponsors_listing
    @frequency = frequency
  end

  private

  attr_reader :sponsors_listing, :frequency

  def render?
    GitHub.sponsors_enabled? && logged_in? && sponsors_listing && !sponsors_listing.disabled?
  end

  memoize def sponsorable
    sponsors_listing.sponsorable
  end

  memoize def has_published_tier?
    sponsors_listing.has_published_tier?
  end

  def suggested_custom_tier_amount
    if sponsors_listing.suggested_custom_tier_amount_in_cents
      sponsors_listing.suggested_custom_tier_amount_in_dollars.to_i
    end
  end

  def min_custom_tier_amount
    if sponsors_listing.min_custom_tier_amount_in_cents
      sponsors_listing.min_custom_tier_amount_in_dollars.to_i
    end
  end

  def one_time_frequency?
    frequency == :one_time
  end

  def frequency_name
    one_time_frequency? ? "one-time" : "monthly"
  end

  # Private: Sponsors only have the possibility of getting a reward for a custom sponsorship when
  # there's a published tier of the same frequency.
  def custom_rewards_possible?
    sponsors_listing
      .sponsors_tiers
      .where(frequency: frequency)
      .with_published_state
      .any?
  end

  memoize def can_disable_custom_amount?
    sponsors_listing.can_disable_custom_amount?
  end

  def form_path
    if one_time_frequency?
      sponsorable_dashboard_custom_tier_settings_path(sponsors_listing.sponsorable_login, frequency: "one-time")
    else
      sponsorable_dashboard_custom_tier_settings_path(sponsors_listing.sponsorable_login)
    end
  end
end
