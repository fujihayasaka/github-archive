# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::LinkStripeAccountComponent < ApplicationComponent
  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  private

  attr_reader :sponsors_listing

  def render?
    GitHub.sponsors_enabled? && sponsors_listing.present?
  end
end
