# typed: strict
# frozen_string_literal: true

module TradeControls
  class ManualCompliance
    include Compliance

    sig { returns(T.any(User, Organization)) }
    attr_reader :actor

    sig { params(actor: T.any(User, Organization), reason: T.nilable(T.any(String, Symbol)), kwargs: T.untyped).void }
    def initialize(actor:, reason: nil, **kwargs)
      @actor = actor
      @reason = T.let(reason.presence || :manual, T.any(String, Symbol))
    end

    sig { override.returns(T.any(String, Symbol)) }
    def reason
      @reason
    end

    sig { override.returns(T::Boolean) }
    def violation?
      true
    end

    sig { override.returns(T::Hash[T.any(Symbol, String), T.untyped]) }
    def to_hydro
      {
        actor: actor,
        reason: reason,
      }
    end

    # Internal: invoked by Instrumentation::Model when expanding event_payload
    sig { override.params(kwargs: T.untyped).returns(T.untyped) }
    def event_context(**kwargs)
      Context::Expander.expand(actor: actor, reason: reason)
    end
  end
end
