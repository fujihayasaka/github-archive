# typed: true
# frozen_string_literal: true

module Configurable
  module CodespaceDefaultTelemetryLevel
    extend T::Helpers

    requires_ancestor { Configurable }

    class InvalidCodespaceTelemetryLevel < ArgumentError; end

    KEY = "codespace_default_telemetry_level"

    def codespace_default_telemetry_level
      config.get(KEY) || Codespaces::Settings::DEFAULT_TELEMETRY_LEVEL
    end

    def update_codespace_default_telemetry_level(level, force = false, actor:)
      changed = if level.nil?
        config.delete(KEY, actor)
      else
        config.set!(KEY, level, actor, force)
      end
      return unless changed
      GitHub.dogstats.increment("codespace_default_telemetry_level.updated")
    end
  end
end
