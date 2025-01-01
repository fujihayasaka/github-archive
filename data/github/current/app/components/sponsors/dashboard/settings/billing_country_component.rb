# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Settings::BillingCountryComponent < ApplicationComponent
  def initialize(sponsorable:)
    @sponsorable = sponsorable
  end

  private

  def render?
    return false unless @sponsorable
    return false if @sponsorable.organization? && @sponsorable.uses_sponsors_fiscal_host?

    !stripe_connect_account && sponsors_listing
  end

  memoize def sponsors_listing
    @sponsorable.sponsors_listing
  end

  memoize def stripe_connect_account
    sponsors_listing.active_stripe_connect_account
  end

  def billing_country
    sponsors_listing.billing_country
  end

  def country_options
    supported_countries = Billing::StripeConnect::Account.supported_countries

    unsanctioned_countries = TradeControls::Countries.currently_unsanctioned
    unsanctioned_countries.each_with_object([]) do |(country_name, alpha2, _, _), options|
      options << [country_name, alpha2] if supported_countries.include?(alpha2)
    end
  end
end
