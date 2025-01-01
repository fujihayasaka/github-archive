# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::TierSuggestions::PreviewComponent < ApplicationComponent
  include AvatarHelper

  def initialize(sponsorable:, tiers:)
    @sponsorable = sponsorable
    @tiers = tiers
    @tier_previews = tier_previews
  end

  private

  def tier_previews
    SponsorsTier.frequencies.keys.map do |frequency|
      {
        frequency: frequency,
        heading: frequency.to_sym == :recurring ? "Monthly tiers" : "One-time tiers",
        tiers: get_tier_previews(frequency: frequency)
      }
    end
  end

  def get_tier_previews(frequency:)
    tiers = Sponsors::TierSuggestion.for_frequency(frequency)
      .sort_by(&:monthly_price_in_cents)
      .group_by(&:name)
  end

  def inspiring_users
    Sponsors::TierSuggestion.inspiring_users
  end

  attr_reader :sponsorable

  def render?
    sponsorable.present?
  end
end
