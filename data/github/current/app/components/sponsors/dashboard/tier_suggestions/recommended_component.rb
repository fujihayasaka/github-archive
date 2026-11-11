# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::TierSuggestions::RecommendedComponent < ApplicationComponent
  def initialize(sponsorable:, tiers:)
    @sponsorable = sponsorable
    @tiers = tiers
    @categorized_tiers = categorized_tiers
  end

  private

  def categorized_tiers
    Sponsors::TierSuggestion.categories.map do |category|
      {
        category: category,
        emoji_alias: Sponsors::TierSuggestion.emoji_alias(category: category),
        tiers: Sponsors::TierSuggestion.for_category(category)
      }
    end
  end

  attr_reader :sponsorable

  def render?
    sponsorable.present?
  end
end
