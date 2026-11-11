# typed: true
# frozen_string_literal: true

class Sponsors::Profile::SponsorAvatarListComponent < ApplicationComponent
  # sponsorships - a WillPaginate::Collection of Sponsorship records
  # sponsorable - a User or Organization that has a SponsorsListing
  # next_page_filter - String representing the filter to use for pagination ("all", "active", "inactive")
  def initialize(sponsorships:, sponsorable:, next_page_filter: "all")
    @sponsorships = sponsorships
    @sponsorable = sponsorable
    @next_page_filter = fetch_or_fallback(Sponsors::SponsorsPartialsController::SPONSORSHIP_PAGINATION_FILTERS, next_page_filter, "all")
    ensure_sponsorships_are_paginated
  end

  private

  attr_reader :sponsorships, :sponsorable, :next_page_filter

  def render?
    sponsorships.total_entries > 0
  end

  def ensure_sponsorships_are_paginated
    raise "sponsorships must be paginated using the .paginate method" unless sponsorships.respond_to?(:total_entries)
  end
end
