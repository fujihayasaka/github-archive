# typed: false
# frozen_string_literal: true

module Configurable
  module Showcase
    KEY = "disable_showcase".freeze

    def enable_showcase(actor)
      config.enable(KEY, actor)
    end

    def disable_showcase(actor)
      config.delete(KEY, actor)
    end

    def showcase_enabled?
      !GitHub.enterprise? || config.enabled?(KEY)
    end

  end
end
