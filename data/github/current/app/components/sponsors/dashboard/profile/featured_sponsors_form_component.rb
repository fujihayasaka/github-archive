# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::FeaturedSponsorsFormComponent < ApplicationComponent
  FORM_ID = "sponsors-featured-sponsorships-search-form"
  RESULTS_CONTAINER_ID = "sponsors-featured-sponsorships-container"

  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  private

  attr_reader :sponsors_listing

  delegate :sponsorable_login, to: :sponsors_listing

  def render?
    sponsors_listing
  end
end
