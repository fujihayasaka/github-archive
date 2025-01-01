# typed: strict
# frozen_string_literal: true

module TradeControls
  class EmailCompliance
    include Compliance
    include DomainFlagging

    sig { params(email: T.nilable(String), event_source: T.nilable(String), kwargs: T.untyped).void }
    def initialize(email:, event_source: nil, **kwargs)
      @email = T.let(email.to_s, String)
      @reason = T.let(:email, Symbol)
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

    sig { override.returns(T::Hash[T.any(Symbol, String), T.untyped]) }
    def to_hydro
      {
        reason: reason,
        country: sanctioned_country&.name,
        email: @email,
      }
    end

    sig { returns(T::Boolean) }
    def sdn_suspend?
      tld&.upcase == "KP"
    end

    # Internal: invoked by Instrumentation::Model when expanding event_payload
    sig { override.params(kwargs: T.untyped).returns(T.untyped) }
    def event_context(**kwargs)
      Context::Expander.expand(email: @email, reason: reason, country: sanctioned_country)
    end

    private

    sig { override.returns(String) }
    def domain_field
      @email
    end

    sig { override.returns(Symbol) }
    def domain_field_type
      :email
    end
  end
end
