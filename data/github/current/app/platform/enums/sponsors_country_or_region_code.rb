# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SponsorsCountryOrRegionCode < Platform::Enums::Base
      description "Represents countries or regions for billing and residence for a GitHub Sponsors profile."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      SponsorsListing.valid_country_codes.each do |code|
        value code, ::Billing::StripeConnect::Account.country_name_for(code)
      end
    end
  end
end
