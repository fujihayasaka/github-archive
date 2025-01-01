# typed: true
# frozen_string_literal: true

class Platform::Models::SponsorsTierAdminInfo
  attr_reader :tier

  # tier - a SponsorsTier
  def initialize(tier)
    @tier = tier
  end

  delegate :published?, :retired?, :draft?, to: :tier
end
