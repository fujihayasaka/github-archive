# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Settings::FiscalHostComponent < ApplicationComponent
  # sponsorable - a User or Organization
  def initialize(sponsorable:)
    @sponsorable = sponsorable
    @listing = @sponsorable&.sponsors_listing
  end

  private

  def render?
    return false unless GitHub.sponsors_enabled? && @sponsorable && @listing
    @listing.uses_fiscal_host? && @listing.can_use_fiscal_host?
  end

  def fiscal_host_name
    @listing.human_fiscal_host
  end

  def contact_us_url
    SponsorsListing.support_url(subject: "GitHub Sponsors: Fiscal Host")
  end
end
