# typed: true
# frozen_string_literal: true

module Configurable
  module CustomModels
    extend Configurable::Async
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "custom_models"

    sig { params(actor: User, force: T::Boolean, instrument: T::Boolean).returns(T::Boolean) }
    def disable_custom_models(actor, force: false, instrument: true)
      return true if local_custom_models_disabled? && !force
      changed = config.disable!(KEY, actor, force)
      return false unless changed

      instrument_github_custom_models_disablement(actor: actor) if instrument
      true
    end

    sig { params(actor: User, force: T::Boolean, instrument: T::Boolean).returns(T::Boolean) }
    def enable_custom_models(actor, force: false, instrument: true)
      return true if local_custom_models_enabled?
      changed = config.enable!(KEY, actor, force)
      return false unless changed

      instrument_github_custom_models_enablement(actor: actor) if instrument
      true
    end

    sig { returns T::Boolean }
    def custom_models_enabled?
      return false if config.raw(KEY).nil?
      config.enabled?(KEY)
    end

    sig { returns T::Boolean }
    def custom_models_disabled?
      config.get(KEY) == false
    end

    # Override in consumers to send appropriate Hydro messages for each receiver type. By default, a no-op.
    sig { params(actor: User).void }
    def instrument_github_custom_models_enablement(actor:)
    end

    # Override in consumers to send appropriate Hydro messages for each receiver type. By default, a no-op.
    sig { params(actor: User).void }
    def instrument_github_custom_models_disablement(actor:)
    end

    async_configurable :custom_models_enabled?

    private

    sig { returns T::Boolean }
    def local_custom_models_enabled?
      config.local?(KEY) && config.raw(KEY) == "true" || false
    end

    sig { returns T::Boolean }
    def local_custom_models_disabled?
      config.local?(KEY) && config.raw(KEY) == "false" || false
    end
  end
end
