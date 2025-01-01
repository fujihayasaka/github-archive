# typed: true
# frozen_string_literal: true

class SponsorsBusinessTaxIdentifier < ApplicationRecord::Domain::Sponsors
  COUNTRY_CODES_WITHOUT_VAT_CODES = ["US"].freeze

  belongs_to :user, required: true

  validates :country, length: { is: 2 }
  validates :region, presence: true
  validate :country_and_region_iso3166_compliant
  validate :country_uses_vat_codes

  def human_country
    Sponsors::ISO3166.countries.fetch(country)
  end

  def human_region
    derived_country = region.split("-").first
    Sponsors::ISO3166.subdivisions(country_code: derived_country).fetch(region)
  end

  private

  def country_and_region_iso3166_compliant
    return errors.add(:country, "is not a valid country") unless Sponsors::ISO3166.countries.include?(country)
    subdivisions = Sponsors::ISO3166.subdivisions(country_code: country)
    errors.add(:region, "is not a valid region for this country") unless subdivisions.include?(region)
  end

  def country_uses_vat_codes
    if vat_code && COUNTRY_CODES_WITHOUT_VAT_CODES.include?(country)
      errors.add(:vat_code, "is not supported for this country")
    end
  end
end
