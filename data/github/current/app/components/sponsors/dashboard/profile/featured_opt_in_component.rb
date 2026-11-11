# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::FeaturedOptInComponent < ApplicationComponent
  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  private

  attr_reader :sponsors_listing

  def render?
    sponsors_listing.present?
  end

  def featured_state_checked?
    !sponsors_listing.featured_disabled?
  end
end
