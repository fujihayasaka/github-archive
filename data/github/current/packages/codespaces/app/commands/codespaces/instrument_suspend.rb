# typed: strict
# frozen_string_literal: true

module Codespaces
  class InstrumentSuspend < Codespaces::Command

    TTL = T.let(5.minutes, ActiveSupport::Duration)

    sig { returns(Codespace) }
    attr_reader :codespace

    sig { returns(T.nilable(User)) }
    attr_reader :actor

    sig { params(codespace: Codespace, actor: T.nilable(User)).void }
    def initialize(codespace:, actor: nil)
      @codespace = codespace
      @actor = actor
    end

    sig { override.void }
    def perform
      instrument_suspend! unless instrumentation_locked?
    end

    private

    sig { returns(T::Boolean) }
    def instrumentation_locked?
      !!kv.get(cache_key).value { false }
    end

    sig { void }
    def instrument_suspend!
      ActiveRecord::Base.connected_to(role: :writing) do
        kv.set(cache_key, codespace.name, expires: TTL.from_now)
        codespace.instrument(:suspend_environment, actor: actor)
      end
    end

    sig { returns(GitHub::KV) }
    def kv
      Codespaces::Kv.store
    end

    sig { returns(String) }
    def cache_key
      "codespaces-instrument-suspend-#{codespace.id}"
    end
  end
end
