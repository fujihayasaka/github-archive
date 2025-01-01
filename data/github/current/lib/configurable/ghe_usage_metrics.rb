# typed: true
# frozen_string_literal: true

# Whether GHES usage metrics upload to dotcom is enabled.
module Configurable
  module GheUsageMetrics
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "usage_metrics".freeze

    def enable_ghe_usage_metrics(actor)
      config.enable(KEY, actor)
    end

    def disable_ghe_usage_metrics(actor)
      config.disable(KEY, actor)
    end

    def ghe_usage_metrics_enabled?
      config.enabled?(KEY)
    end
  end
end
