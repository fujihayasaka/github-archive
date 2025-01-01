# typed: true
# frozen_string_literal: true

# See https://www.iso.org/iso-3166-country-codes.html
module Sponsors::ISO3166
  ## Public: Get a mapping of country codes to country names.
  #
  # Returns a Hash of country_code => country_name sorted by country name.
  def self.countries
    countries = country_data.map { |country_code, country_data| [country_code, country_data["name"]] }
    countries
      .sort_by { |_code, name| name }
      .to_h
  end

  ## Public: Get a mapping of subdivision codes to subdivision names for a given country. Subdivisions are
  # things like states/territories for the U.S. (e.g. "US-AL" => "Alabama") or provinces for Canada (e.g. "CA-QC" =>
  # "Quebec") as defined by ISO3166-2. Subdivisions are prefixed by the 2-letter country code and separated by a dash.
  # If a country has no defined subdivisions, a single empty subdivision will be returned, e.g. "AQ-" => "Antarctica"
  # for the subdivisions of Antarctica as it has no subdivisions defined.
  #
  # country_code - ISO3166 2-letter country code, e.g., "US" for United States
  #
  # Returns a Hash of subdivision_code => subdivision_name sorted by subdivision name, e.g. "US-CA" => "California"
  def self.subdivisions(country_code:)
    return {} if !country_data.key?(country_code)

    subdivisions = country_data[country_code]["subdivisions"].map do |subdivision_code, subdivision_name|
      [subdivision_code, subdivision_name]
    end
    subdivisions
      .sort_by { |_code, name| name }
      .to_h
  end

  def self.country_data
    return @data if defined?(@data)
    data_file = File.join(Rails.root, "config/sponsors-iso3166.json")
    @data = File.open(data_file) { |fp| JSON.parse(fp.read) }
  end

  private_class_method :country_data
end
