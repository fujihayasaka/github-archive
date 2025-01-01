# typed: strict
# frozen_string_literal: true

module Licensing::GeoComplianceHelper
  # Check if enterprise server licenses should be blocked for geographic reasons
  # Blocks if user's billing info OR trade controls country is from high-risk geo
  # For businesses: only billing contact country matters (no trade controls restrictions)
  # For users: checks both trade controls restriction country and billing contact country
  sig { params(business: Business, user: T.nilable(User)).returns(T::Boolean) }
  def license_access_geo_blocked?(business:, user:)
    return false unless user

    user_inferred_country = extract_user_country(user)
    user_billing_country = user.billing_contact.country
    business_country = business.billing_contact.country

    TradeControls::Countries.ghes_blocked_countries.any? do |blocked_country|
      user_inferred_country == blocked_country || user_billing_country == blocked_country || business_country == blocked_country
    end
  end

  private

  sig { params(user: User).returns(T.nilable(TradeControls::Country)) }
  def extract_user_country(user)
    if restriction_code = user.trade_controls_restriction.trade_restricted_country_code
      country_code = restriction_code.split(" -- ").first
      country_from_code(country_code) if country_code
    end
  end

  # Convert country code string to TradeControls::Country object
  sig { params(country_code: String).returns(T.nilable(TradeControls::Country)) }
  def country_from_code(country_code)
    country_info = Braintree::Address::CountryNames.find do |_, alpha2, alpha3, _|
      alpha3&.upcase == country_code.upcase || alpha2&.upcase == country_code.upcase
    end

    country_info ? TradeControls::Country.from_braintree(country_info) : nil
  end
end
