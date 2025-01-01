# typed: true
# frozen_string_literal: true

module Configurable
  module CodespaceDefaultRetentionPeriod
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    class InvalidCodespaceRetentionPeriod < ArgumentError; end

    KEY = "codespace_default_retention_period"

    def codespace_default_retention_period
      config.int(KEY)
    end

    def update_codespace_default_retention_period(period, force = false, actor:)
      changed = if period.nil?
        config.delete(KEY, actor)
      else
        raise InvalidCodespaceRetentionPeriod if period&.to_i > Codespace::MAX_RETENTION_PERIOD
        config.set!(KEY, period&.to_i, actor, force)
      end

      return unless changed

      GitHub.dogstats.increment("codespace_default_retention_period.updated")
    end
  end
end
