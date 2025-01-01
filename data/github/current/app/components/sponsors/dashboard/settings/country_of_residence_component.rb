# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Settings::CountryOfResidenceComponent < ApplicationComponent
  def initialize(sponsorable:, return_to: nil, disable_stripe_links: false)
    @sponsorable = sponsorable
    @listing = sponsorable&.sponsors_listing
    @return_to = return_to
    @disable_stripe_links = disable_stripe_links
  end

  private

  attr_reader :sponsorable, :listing, :return_to

  def render?
    sponsorable&.user? && listing && GitHub.sponsors_enabled?
  end

  memoize def stripe_country
    stripe_account&.country
  end

  memoize def country_of_residence
    listing.country_of_residence
  end

  memoize def has_errors?
    !listing.has_country_of_residence?
  end

  memoize def country_of_residence_options
    TradeControls::Countries.currently_unsanctioned.map do |country_name, alpha2, _, _|
      [country_name, alpha2]
    end
  end

  memoize def stripe_account
    listing.active_stripe_connect_account
  end

  def hide_stripe_link?
    @disable_stripe_links
  end
end
