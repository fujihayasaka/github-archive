# typed: true
# frozen_string_literal: true

class Platform::Models::MarketplaceListingAdminInfo
  attr_reader :listing

  def initialize(listing)
    @listing = listing
  end
end
