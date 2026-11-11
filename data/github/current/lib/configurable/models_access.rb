# typed: true
# frozen_string_literal: true

module Configurable
  module ModelsAccess
    extend Configurable::Async
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "models_access"

    sig { params(actor: User, force: T::Boolean, instrument: T::Boolean).returns(T::Boolean) }
    def disable_models_access(actor, force: false, instrument: true)
      return true if local_config_disabled? && !force

      changed = config.disable!(KEY, actor, force)
      return false unless changed

      instrument_github_models_disablement(actor: actor) if instrument
      true
    end

    sig { params(actor: User, force: T::Boolean, instrument: T::Boolean).returns(T::Boolean) }
    def enable_models_access(actor, force: false, instrument: true)
      return true if local_config_enabled?

      changed = config.enable!(KEY, actor, force)
      return false unless changed

      instrument_github_models_enablement(actor: actor) if instrument
      true
    end

    sig { params(actor: User, value: String, force: T::Boolean).returns(T::Boolean) }
    def set_models_access(actor, value, force: false)
      config.set!(KEY, value, actor, force)
    end

    # Override in consumers to change whether Models should be enabled by default when it has not been explicitly set
    # for the consumer yet.
    sig { returns T::Boolean }
    def default_enabled_status
      false
    end

    # Override in consumers to send appropriate Hydro messages for each receiver type. By default, a no-op.
    sig { params(actor: User).void }
    def instrument_github_models_disablement(actor:)
    end

    # Override in consumers to send appropriate Hydro messages for each receiver type. By default, a no-op.
    sig { params(actor: User).void }
    def instrument_github_models_enablement(actor:)
    end

    private

    def local_config_enabled?
      config.local?(KEY) && config.raw(KEY) == "true"
    end

    def local_config_disabled?
      config.local?(KEY) && config.raw(KEY) == "false"
    end
  end
end
