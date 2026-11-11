# typed: strict
# frozen_string_literal: true

module TradeControls
  module LocationEntity
    include Comparable

    sig { returns(T.nilable(String)) }
    attr_reader :name

    sig { returns(T.nilable(String)) }
    attr_reader :alpha2

    sig { returns(T.nilable(String)) }
    attr_reader :alpha3

    sig { returns(T.nilable(String)) }
    attr_reader :domain

    sig { returns(T.nilable(String)) }
    attr_reader :region_name

    sig { returns(T.nilable(String)) }
    attr_reader :region_code

    sig { returns(T.nilable(String)) }
    attr_reader :city

    sig { params(name: T.nilable(String), alpha2: T.nilable(String), alpha3: T.nilable(String), domain: T.nilable(String), city: T.nilable(String), region: T::Hash[Symbol, T.nilable(String)]).void }
    def initialize(name: nil, alpha2: nil, alpha3: nil, domain: nil, city: nil, region: {})
      @name = T.let(name, T.nilable(String))
      @alpha2 = T.let(alpha2&.upcase, T.nilable(String)) # ISO 3166-1 alpha-2
      @alpha3 = T.let(alpha3&.upcase, T.nilable(String)) # ISO 3166-1 alpha-3
      @domain = T.let(domain&.downcase, T.nilable(String))
      @city = T.let(city, T.nilable(String))
      @region_name = T.let(region[:name], T.nilable(String))
      @region_code = T.let(region[:code]&.to_s&.upcase, T.nilable(String)) # ISO 3166-2
    end

    # Compares loose value equality using any of name/alpha2/alpha3/domain.
    # (Since all of these properties are unique to a country.)
    sig { params(other: T.any(TradeControls::Country, TradeControls::City)).returns(T::Boolean) }
    def ==(other)
      !!(name.present? && name == other.name) ||
        !!(alpha2.present? && alpha2 == other.alpha2) ||
        !!(alpha3.present? && alpha3 == other.alpha3) ||
        !!(domain.present? && domain == other.domain)
    end
    alias_method :same_country?, :==

    sig { params(other: T.any(TradeControls::Country, TradeControls::City)).returns(T::Boolean) }
    def same_region?(other)
      region_code == other.region_code || region_name == other.region_name
    end

    # ISO 3166-2
    sig { returns(String) }
    def subdivision_code
      "#{alpha2}-#{region_code}"
    end

    sig { returns(T::Boolean) }
    def region?
      region_code.present? || region_name.present?
    end

    sig { returns(T::Boolean) }
    def city?
      city.present?
    end
  end
end
