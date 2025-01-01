# typed: strict
# frozen_string_literal: true

module TradeControls
  class IpCompliance
    include Compliance
    include GitHub::Memoizer

    sig { params(ip: T.nilable(String), location: T::Hash[Symbol, String], event_source: T.nilable(String), kwargs: T.untyped).void }
    def initialize(ip:, location:, event_source: nil, **kwargs)
      @ip = ip
      @reason = T.let(:ip, Symbol)
      @location = location
      @event_source = event_source
    end

    sig { override.returns(T.any(String, Symbol)) }
    def reason
      @reason
    end

    sig { override.returns(T.nilable(String)) }
    def event_source
      @event_source
    end

    sig { override.returns(T::Boolean) }
    def violation?
      sanctioned_country.present?
    end

    sig { override.returns(T::Hash[T.any(Symbol, String), T.untyped]) }
    def to_hydro
      {
        reason: reason,
        country: sanctioned_country&.name,
        region: sanctioned_country&.region_name,
        ip: @ip,
      }
    end

    # Internal: invoked by Instrumentation::Model when expanding event_payload
    sig { override.params(kwargs: T.untyped).returns(T.untyped) }
    def event_context(**kwargs)
      Context::Expander.expand(ip: @ip, reason: reason, country: sanctioned_country)
    end

    private

    sig { returns(TradeControls::Country) }
    memoize def inferred_country
      Country.from_location(@location)
    end

    sig { returns(TradeControls::City) }
    memoize def inferred_city
      City.from_location(@location)
    end

    sig { returns(T.nilable(T.any(TradeControls::Country, TradeControls::City))) }
    memoize def sanctioned_country
      return nil unless inferred_country.present?

      if inferred_city.high_risk?
        Cities::HIGH_RISK_CITIES.find { |c| c.same_city?(inferred_city) }
      else
        Countries::SANCTIONED.find { |c| c == inferred_country } ||
        Countries::SANCTIONED_REGIONS.find { |c| c.eql? inferred_country }
      end
    end
  end
end
