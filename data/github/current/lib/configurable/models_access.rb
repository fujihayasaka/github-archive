# typed: true
# frozen_string_literal: true

module Configurable
  module ModelsAccess
    extend Configurable::Async
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "models_access"

    sig { params(actor: User, instrument: T::Boolean).returns(T::Boolean) }
    def disable_models_access(actor, instrument: true)
      return true unless models_access_enabled?

      changed = config.delete(KEY, actor)
      return false unless changed

      instrument_github_models_disablement(actor: actor) if instrument
      true
    end

    sig { params(actor: User, instrument: T::Boolean).returns(T::Boolean) }
    def enable_models_access(actor, instrument: true)
      return true if models_access_enabled?

      changed = config.enable(KEY, actor)
      return false unless changed

      instrument_github_models_enablement(actor: actor) if instrument
      true
    end

    sig { returns T::Boolean }
    def models_access_enabled?
      config.enabled?(KEY)
    end

    # Override in consumers to send appropriate Hydro messages for each receiver type. By default, a no-op.
    sig { params(actor: User).void }
    def instrument_github_models_disablement(actor:)
    end

    # Override in consumers to send appropriate Hydro messages for each receiver type. By default, a no-op.
    sig { params(actor: User).void }
    def instrument_github_models_enablement(actor:)
    end

    async_configurable :models_access_enabled?
  end
end
