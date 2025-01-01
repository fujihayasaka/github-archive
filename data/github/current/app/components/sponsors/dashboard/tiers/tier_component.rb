# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Tiers::TierComponent < ApplicationComponent
  def initialize(sponsors_tier:, sponsor_count:)
    @tier = sponsors_tier
    @sponsor_count = sponsor_count
  end

  private

  attr_reader :tier, :sponsor_count

  delegate :sponsors_listing, :sponsorable, :repository, to: :tier

  def render?
    tier.present?
  end

  memoize def has_repository?
    tier.has_repository?
  end

  memoize def repository_errors
    tier.sponsors_only_repository_errors
  end
end
