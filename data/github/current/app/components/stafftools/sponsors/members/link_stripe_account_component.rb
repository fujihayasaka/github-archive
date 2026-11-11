# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::LinkStripeAccountComponent < ApplicationComponent
  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  private

  attr_reader :sponsors_listing

  # Memoize to avoid duplicate COUNT queries when referenced multiple times in template.
  memoize def within_stripe_account_limit?
    sponsors_listing.within_stripe_account_limit?
  end

  def render?
    GitHub.sponsors_enabled? && sponsors_listing.present?
  end
end
