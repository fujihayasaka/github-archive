# typed: true
# frozen_string_literal: true

module Configurable
  module ModelsBilling
    extend Configurable::Async
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "models_billing"

    sig { params(actor: User, force: T::Boolean, instrument: T::Boolean).returns(T::Boolean) }
    def disable_models_billing(actor, force: false, instrument: true)
      return true unless models_billing_enabled? || force

      changed = config.disable!(KEY, actor, force)
      return false unless changed

      instrument_github_models_billing_disablement(actor: actor) if instrument
      true
    end

    sig { params(actor: User, force: T::Boolean, instrument: T::Boolean).returns(T::Boolean) }
    def enable_models_billing(actor, force: false, instrument: true)
      return true if models_billing_enabled?

      changed = config.enable!(KEY, actor, force)
      return false unless changed

      enable_models_on_billing
      instrument_github_models_billing_enablement(actor: actor) if instrument
      true
    end

    sig { returns T::Boolean }
    def models_billing_enabled?
      if config.raw(KEY).nil? # config not yet set
        default_billing_enabled_status
      else # config explicitly set to something
        config.enabled?(KEY)
      end
    end

    sig { returns T::Boolean }
    def models_billing_disabled?
      config.get(KEY) == false
    end

    # Override in consumers to change whether Models should be enabled by default when it has not been explicitly set
    # for the consumer yet.
    sig { returns T::Boolean }
    def default_billing_enabled_status
      false
    end

    # Override in consumers to send appropriate Hydro messages for each receiver type. By default, a no-op.
    sig { params(actor: User).void }
    def instrument_github_models_billing_enablement(actor:)
    end

    # Override in consumers to send appropriate Hydro messages for each receiver type. By default, a no-op.
    sig { params(actor: User).void }
    def instrument_github_models_billing_disablement(actor:)
    end

    # Override in consumers to take appropriate actions when Models billing is enabled. By default, a no-op.
    sig { void }
    def enable_models_on_billing
    end

    async_configurable :models_billing_enabled?
  end
end
