# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::ChildListings::IndexComponent < ApplicationComponent
  def initialize(child_listings:, sponsors_listing:)
    @child_listings = child_listings || []
    @sponsors_listing = sponsors_listing
  end

  private

  attr_reader :child_listings, :sponsors_listing

  delegate :sponsorable_login, to: :sponsors_listing

  def render?
    sponsors_listing.present? && sponsors_listing.fiscal_host?
  end

  def child_listings_count
    @child_listings.any? ? @child_listings.total_entries : 0
  end

  def child_listings_pages
    @child_listings.any? ? @child_listings.total_pages : 0
  end
end
