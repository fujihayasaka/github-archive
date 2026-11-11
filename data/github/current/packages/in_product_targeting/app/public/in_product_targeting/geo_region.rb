# typed: strict
# frozen_string_literal: true

module InProductTargeting
  # Provides geographic region constants and helper methods for targeting
  # nudges and in-product messages to users based on their IP-derived country.
  #
  # Usage in nudge components:
  #   return false unless InProductTargeting::GeoRegion.in_amer?(req.remote_ip) || Rails.env.development?
  #   return false unless InProductTargeting::GeoRegion.in_emea?(req.remote_ip) || Rails.env.development?
  #   return false unless InProductTargeting::GeoRegion.in_apac?(req.remote_ip) || Rails.env.development?
  #   return false unless InProductTargeting::GeoRegion.in_regions?(req.remote_ip, :amer, :emea) || Rails.env.development?
  module GeoRegion
    # AMER sub-regions
    NORTH_AMERICA_COUNTRY_CODES = T.let(%w[
      US CA MX
    ].freeze, T::Array[String])

    CENTRAL_AMERICA_COUNTRY_CODES = T.let(%w[
      BZ CR SV GT HN NI PA
    ].freeze, T::Array[String])

    SOUTH_AMERICA_COUNTRY_CODES = T.let(%w[
      AR BO BR CL CO EC PY PE UY VE
    ].freeze, T::Array[String])

    # Americas — union of North, Central, and South America
    AMER_COUNTRY_CODES = T.let((
      NORTH_AMERICA_COUNTRY_CODES +
      CENTRAL_AMERICA_COUNTRY_CODES +
      SOUTH_AMERICA_COUNTRY_CODES
    ).freeze, T::Array[String])

    # APAC sub-regions
    OCEANIA_COUNTRY_CODES = T.let(%w[
      AU NZ
    ].freeze, T::Array[String])

    EAST_ASIA_COUNTRY_CODES = T.let(%w[
      JP KR TW HK
    ].freeze, T::Array[String])

    SOUTHEAST_ASIA_COUNTRY_CODES = T.let(%w[
      KH ID MY PH SG TH VN
    ].freeze, T::Array[String])

    SOUTH_ASIA_COUNTRY_CODES = T.let(%w[
      IN
    ].freeze, T::Array[String])

    # Asia-Pacific — union of Oceania, East Asia, Southeast Asia, and South Asia
    APAC_COUNTRY_CODES = T.let((
      OCEANIA_COUNTRY_CODES +
      EAST_ASIA_COUNTRY_CODES +
      SOUTHEAST_ASIA_COUNTRY_CODES +
      SOUTH_ASIA_COUNTRY_CODES
    ).freeze, T::Array[String])

    # EMEA sub-regions (Africa intentionally excluded for now)
    EUROPE_COUNTRY_CODES = T.let(%w[
      GB IE FR DE NL ES IT SE AT CH
    ].freeze, T::Array[String])

    MIDDLE_EAST_COUNTRY_CODES = T.let(%w[
      IL
    ].freeze, T::Array[String])

    # Europe, Middle East & Africa — currently the union of Europe and the Middle East.
    # Africa is intentionally not included in this list.
    EMEA_COUNTRY_CODES = T.let((
      EUROPE_COUNTRY_CODES +
      MIDDLE_EAST_COUNTRY_CODES
    ).freeze, T::Array[String])

    REGIONS = T.let({
      amer: AMER_COUNTRY_CODES,
      emea: EMEA_COUNTRY_CODES,
      apac: APAC_COUNTRY_CODES,
      north_america: NORTH_AMERICA_COUNTRY_CODES,
      central_america: CENTRAL_AMERICA_COUNTRY_CODES,
      south_america: SOUTH_AMERICA_COUNTRY_CODES,
      europe: EUROPE_COUNTRY_CODES,
      middle_east: MIDDLE_EAST_COUNTRY_CODES,
      oceania: OCEANIA_COUNTRY_CODES,
      east_asia: EAST_ASIA_COUNTRY_CODES,
      southeast_asia: SOUTHEAST_ASIA_COUNTRY_CODES,
      south_asia: SOUTH_ASIA_COUNTRY_CODES,
    }.freeze, T::Hash[Symbol, T::Array[String]])

    # Returns the country code for the given IP address.
    sig { params(ip: String).returns(T.nilable(String)) }
    def self.country_code_for_ip(ip)
      GitHub::Location.look_up(ip)[:country_code]
    end

    # Returns true if the IP address resolves to a country in the AMER region.
    sig { params(ip: String).returns(T::Boolean) }
    def self.in_amer?(ip)
      AMER_COUNTRY_CODES.include?(country_code_for_ip(ip).to_s)
    end

    # Returns true if the IP address resolves to a country in North America.
    sig { params(ip: String).returns(T::Boolean) }
    def self.in_north_america?(ip)
      NORTH_AMERICA_COUNTRY_CODES.include?(country_code_for_ip(ip).to_s)
    end

    # Returns true if the IP address resolves to a country in Central America.
    sig { params(ip: String).returns(T::Boolean) }
    def self.in_central_america?(ip)
      CENTRAL_AMERICA_COUNTRY_CODES.include?(country_code_for_ip(ip).to_s)
    end

    # Returns true if the IP address resolves to a country in South America.
    sig { params(ip: String).returns(T::Boolean) }
    def self.in_south_america?(ip)
      SOUTH_AMERICA_COUNTRY_CODES.include?(country_code_for_ip(ip).to_s)
    end

    # Returns true if the IP address resolves to a country in the EMEA region.
    sig { params(ip: String).returns(T::Boolean) }
    def self.in_emea?(ip)
      EMEA_COUNTRY_CODES.include?(country_code_for_ip(ip).to_s)
    end

    # Returns true if the IP address resolves to a country in Europe.
    sig { params(ip: String).returns(T::Boolean) }
    def self.in_europe?(ip)
      EUROPE_COUNTRY_CODES.include?(country_code_for_ip(ip).to_s)
    end

    # Returns true if the IP address resolves to a country in the Middle East.
    sig { params(ip: String).returns(T::Boolean) }
    def self.in_middle_east?(ip)
      MIDDLE_EAST_COUNTRY_CODES.include?(country_code_for_ip(ip).to_s)
    end

    # Returns true if the IP address resolves to a country in the APAC region.
    sig { params(ip: String).returns(T::Boolean) }
    def self.in_apac?(ip)
      APAC_COUNTRY_CODES.include?(country_code_for_ip(ip).to_s)
    end

    # Returns true if the IP address resolves to a country in Oceania.
    sig { params(ip: String).returns(T::Boolean) }
    def self.in_oceania?(ip)
      OCEANIA_COUNTRY_CODES.include?(country_code_for_ip(ip).to_s)
    end

    # Returns true if the IP address resolves to a country in East Asia.
    sig { params(ip: String).returns(T::Boolean) }
    def self.in_east_asia?(ip)
      EAST_ASIA_COUNTRY_CODES.include?(country_code_for_ip(ip).to_s)
    end

    # Returns true if the IP address resolves to a country in Southeast Asia.
    sig { params(ip: String).returns(T::Boolean) }
    def self.in_southeast_asia?(ip)
      SOUTHEAST_ASIA_COUNTRY_CODES.include?(country_code_for_ip(ip).to_s)
    end

    # Returns true if the IP address resolves to a country in South Asia.
    sig { params(ip: String).returns(T::Boolean) }
    def self.in_south_asia?(ip)
      SOUTH_ASIA_COUNTRY_CODES.include?(country_code_for_ip(ip).to_s)
    end

    # Returns true if the IP address resolves to a country in any of the given regions.
    #
    # Example:
    #   GeoRegion.in_regions?(ip, :amer, :emea)
    sig { params(ip: String, regions: Symbol).returns(T::Boolean) }
    def self.in_regions?(ip, *regions)
      code = country_code_for_ip(ip).to_s
      regions.any? { |region| REGIONS.fetch(region, []).include?(code) }
    end
  end
end
