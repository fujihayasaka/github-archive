# typed: true
# frozen_string_literal: true

module Configurable
  module ModelsAccess
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "models_access"

    def disable_models_access(actor)
      config.delete(KEY, actor)
    end

    def enable_models_access(actor)
      config.enable(KEY, actor)
    end

    def models_access_enabled?
      config.enabled?(KEY)
    end
  end
end
