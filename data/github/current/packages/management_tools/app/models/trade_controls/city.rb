# typed: strict
# frozen_string_literal: true

module TradeControls
  class City
    include LocationEntity

    sig { params(location: T::Hash[Symbol, String]).returns(TradeControls::City) }
    def self.from_location(location)
      new(
        city: location[:city],
        alpha2: location[:country_code],
        region: {
          name: location[:region_name],
          code: location[:region],
        })
    end

    sig { returns(T::Boolean) }
    def high_risk?
      return false unless city?
      return false unless Countries::REGIONS_WITH_CITY_ENFORCEMENT.region_name_downcase.include?(region_name&.downcase)

      Cities.new.high_risk_cities_downcase.include?(city&.downcase)
    end

    # Compares stricter value equality by requiring that region name or region code in addition to city also match.
    sig { params(other: TradeControls::City).returns(T::Boolean) }
    def eql?(other)
      same_country_and_region = same_country?(other) && same_region?(other)
      return same_country_and_region unless city? && other.city?

      same_country_and_region && city == other.city
    end
    alias_method :same_city?, :eql?

    # Internal: invoked by Instrumentation::Model when expanding event_payload
    sig { params(prefix: Symbol).returns(T::Hash[String, String]) }
    def event_context(prefix: :country)
      region = region? ? { region: region_name, region_code: region_code } : {}
      city = city? ? { city: self.city } : {}

      {
        prefix => name,
        :"#{prefix}_code" => alpha2,
        **city,
        **region,
      }
    end
  end
end
