# typed: true
# frozen_string_literal: true

# Public: A Plain Old Ruby Object (PORO) for saving a SponsorsBusinessTaxIdentifier
#
# Only creates a new tax identifier record if this is the sponsor's first one,
# or if the initialized tax information is different than the one newest one
# saved for the sponsor
module Sponsors
  class SaveSponsorsBusinessTaxIdentifier
    class UnprocessableError < StandardError; end

    # inputs - Hash containing attributes to create a tax identifier
    #
    # inputs[:user] - A User or Organization that represents the sponsor
    # inputs[:country] - 2 character ISO country code
    # inputs[:region] - ISO region code
    # inputs[:vat_code] - VAT number/tax identification number
    def self.call(inputs)
      new(**inputs).call
    end

    def initialize(user:, country:, region:, vat_code:)
      @user = user
      @country = country
      @region = region
      @vat_code = vat_code
    end

    def call
      if tax_information_has_changed?
        record = SponsorsBusinessTaxIdentifier.new(
          user: user,
          country: country,
          region: region,
          vat_code: vat_code
        )
        unless record.save
          error_messages = record.errors.full_messages.to_sentence
          raise UnprocessableError.new("Could not save tax info: #{error_messages}")
        end
      end
    end

    private

    attr_reader :user, :country, :region, :vat_code

    def tax_information_has_changed?
      existing_tax_info = user.newest_sponsors_business_tax_identifier
      return true if existing_tax_info.nil?
      existing_tax_info.assign_attributes(
        country: country,
        region: region,
        vat_code: vat_code
      )
      existing_tax_info.changed?
    end
  end
end
