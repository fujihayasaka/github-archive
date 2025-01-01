# typed: true
# frozen_string_literal: true

# Public: A Plain Old Ruby Object (PORO) for Sponsors-relevant
# attributes of a given time zone.
class Sponsors::TimeZone
  # Add support for mismatches between browser and Rails time zone implementations
  # See https://github.com/github/sponsors/issues/3747 as an example
  SPECIAL_CASES = {
    "IN" => ["Asia/Calcutta"]
  }.freeze
  private_constant :SPECIAL_CASES

  # time_zone - A String representing an IANA time zone name (e.g. "America/Chicago", "Asia/Tokyo")
  def initialize(time_zone)
    @time_zone = time_zone
  end

  # Public: Is this time zone within a region supported by GitHub Sponsors?
  #
  # Return a Boolean
  def supported?
    self.class.supported_names.include?(@time_zone)
  end

  # Public: Does this time zone match the given country code?
  #
  # country_code - ISO3166 2-letter country code String (e.g. "US")
  #
  # Returns a Boolean
  def matches_country_code?(country_code)
    self.class.time_zone_names(country_code: country_code).include?(@time_zone)
  end

  # Public: Returns a Set of all supported IANA time zone name Strings
  #
  # e.g. <Set: {"America/Chicago", "Asia/Tokyo", ...}>
  def self.supported_names
    return @@_supported_time_zone_names if defined?(@@_supported_time_zone_names)
    @@_supported_time_zone_names = Set.new

    supported_time_zone_names_by_country.each do |_country, time_zone_names|
      @@_supported_time_zone_names |= time_zone_names
    end

    @@_supported_time_zone_names
  end

  # Public: Returns a Set of IANA time zone name Strings for a given country code
  #
  # country - optional ISO3166 2-letter country code String (e.g. "US") to filter results
  #
  # e.g. <Set: {"America/Chicage", "Asia/Tokyo", ...}>
  def self.names(country_code:)
    # we cache the supported time zones for faster lookup, look there first before falling back
    supported_time_zone_names_by_country[country_code] || time_zone_names(country_code: country_code)
  end

  # Private: Returns a Hash mapping of ISO3166-1 Alpha2 country code Strings to Sets of IANA time zone name Strings
  #
  # e.g. { "US" => <Set: {"America/Chicago", ...}>, "JP" => <Set: {"Asia/Tokyo", ...}> }
  private_class_method def self.supported_time_zone_names_by_country
    return @@_supported_time_zone_names_by_country if defined?(@@_supported_time_zone_names_by_country)

    supported_countries = ::Billing::StripeConnect::Account.supported_countries

    @@_supported_time_zone_names_by_county = supported_countries.each_with_object({}) do |country_code, hash|
      hash[country_code] = time_zone_names(country_code: country_code)
    end
  end

  # Internal: Returns a Set of ISO3166-1 Alpha2 country code Strings for a given country
  #
  # e.g. <Set: {"America/Chicago", "America/New_York", ...}>
  def self.time_zone_names(country_code:)
    country_time_zone_names = begin
      Set.new(ActiveSupport::TimeZone.country_zones(country_code).map(&:name))
    rescue TZInfo::InvalidCountryCode
      Set.new
    end
    # Include aliases like "America/Chicago" for supported zones like "Central Time (US & Canada)":
    aliases = country_time_zone_names
      .map { |time_zone_name| ActiveSupport::TimeZone::MAPPING[time_zone_name] }
      .compact
    country_time_zone_names | Set.new(aliases) | SPECIAL_CASES[country_code].to_a
  end
end
