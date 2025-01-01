# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::UsingFiscalHostFormComponent < ApplicationComponent
  # sponsors_listing - a SponsorsListing
  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  private

  attr_reader :sponsors_listing

  delegate :parent_listing, :parent_sponsorable_login, :sponsorable_login, :for_organization?, to: :sponsors_listing

  def render?
    return false unless sponsors_listing && logged_in? && GitHub.sponsors_enabled?
    sponsors_listing.can_use_fiscal_host?
  end

  def fiscal_host_listings
    SponsorsListing.fiscal_hosts.ordered_by_sponsorable_login.includes(sponsorable: :profile)
  end
end
