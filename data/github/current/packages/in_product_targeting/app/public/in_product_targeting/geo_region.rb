# typed: strict
# frozen_string_literal: true

module InProductTargeting
  # Provides geographic region constants and helper methods for targeting
  # nudges and in-product messages to users based on their IP-derived country.
  #
  # Usage in nudge components:
  #   return false unless InProductTargeting::GeoRegion.in_amer?(req.remote_ip) || Rails.env.development?
  #   return false unless InProductTargeting::GeoRegion.in_emea?(req.remote_ip) || Rails.env.development?
  #   return false unless InProductTargeting::GeoRegion.in_regions?(req.remote_ip, :amer, :emea) || Rails.env.development?
  module GeoRegion
    # Americas — currently scoped to the United States
    AMER_COUNTRY_CODES = T.let(%w[
      US
    ].freeze, T::Array[String])

    # Europe, Middle East & Africa
    EMEA_COUNTRY_CODES = T.let(%w[
      DE AT CH
      GB IE
      BE NL LU
      SE DK NO FI IS
      FR ES IT PT
      IL
      PL CZ SK HU RO BG
      GR TR CY
      AL BA HR XK ME MK RS SI
      DZ AO BJ BW BF BI CV CF TD KM CD DJ EG GQ ER SZ ET GA GM GH GN GW CI
      KE LS LR LY MG MW ML MR MU MA MZ NA NE NG CG RW ST SN SC SL SO ZA SS
      SD TZ TG TN UG ZM ZW
      BH IQ JO KW LB OM PS QA SA SY AE YE
      UA
    ].freeze, T::Array[String])

    REGIONS = T.let({
      amer: AMER_COUNTRY_CODES,
      emea: EMEA_COUNTRY_CODES,
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

    # Returns true if the IP address resolves to a country in the EMEA region.
    sig { params(ip: String).returns(T::Boolean) }
    def self.in_emea?(ip)
      EMEA_COUNTRY_CODES.include?(country_code_for_ip(ip).to_s)
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
