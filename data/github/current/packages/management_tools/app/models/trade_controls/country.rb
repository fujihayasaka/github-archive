# typed: strict
# frozen_string_literal: true

module TradeControls
  # A Value Object class that represents a country/region.
  #
  # In the future, it may become a proper Active Record model.
  class Country
    extend T::Sig
    include LocationEntity

    sig { params(braintree_country: T.nilable(T::Array[String])).returns(TradeControls::Country) }
    def self.from_braintree(braintree_country)
      name, alpha2, alpha3, * = braintree_country
      new(
        name: name,
        alpha2: alpha2,
        alpha3: alpha3,
        domain: alpha2&.downcase)
    end

    sig { params(domain: String).returns(TradeControls::Country) }
    def self.from_domain(domain)
      new(domain: domain)
    end

    sig { params(ip: String).returns(TradeControls::Country) }
    def self.from_ip(ip)
      from_location GitHub::Location.look_up(ip)
    end

    sig { params(location: T::Hash[Symbol, String]).returns(TradeControls::Country) }
    def self.from_location(location)
      # skipping name and alpha3 b/c we haven't matched countries by them before
      # name: location[:country_name],
      # alpha3: location[:country_code3],
      new(
        alpha2: location[:country_code],
        region: {
          name: location[:region_name],
          code: location[:region],
        })
    end

    # As this may become an ActiveRecord model, the `update` method name was
    # leveraged as the semantics are similar: the result of calling `update`
    # is a Country instance with the same prior attributes set,
    # plus the given attributes set.
    #
    # As an AR model, it mutates the record in the db, of course. But for
    # a Value Object, it returns a new instance with the attributes merged.
    sig { params(attributes: T.untyped).returns(TradeControls::Country) }
    def update(**attributes)
      self.class.new(
        name: name,
        alpha2: alpha2,
        alpha3: alpha3,
        domain: domain,
        region: { name: region_name, code: region_code },
        **attributes)
    end

    # Compares for sortability using country code + region code
    sig { params(other: TradeControls::Country).returns(T.nilable(Integer)) }
    def <=>(other)
      subdivision_code <=> other.subdivision_code
    end

    # Compares slightly stricter value equality by (in addition to ==),
    # requiring that region name or region code also match.
    sig { params(other: TradeControls::Country).returns(T::Boolean) }
    def eql?(other)
      # the same_country? check here is likely redundant since
      # region name/code should be unique across all countries.
      same_country?(other) && same_region?(other)
    end

    # Internal: invoked by Instrumentation::Model when expanding event_payload
    sig { params(prefix: Symbol).returns(T::Hash[String, String]) }
    def event_context(prefix: :country)
      region = region? ? { region: region_name, region_code: region_code } : {}

      {
        prefix => name,
        :"#{prefix}_code" => alpha2,
        **region,
      }
    end
  end
end
