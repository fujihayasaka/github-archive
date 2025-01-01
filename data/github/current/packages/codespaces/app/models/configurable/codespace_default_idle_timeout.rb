# typed: true
# frozen_string_literal: true

module Configurable
  module CodespaceDefaultIdleTimeout
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    class InvalidCodespaceIdleTimeout < ArgumentError; end

    KEY = "codespace_default_idle_timeout"

    def codespace_default_idle_timeout
      config.int(KEY)
    end

    def update_codespace_default_idle_timeout(timeout, force = false, actor:)
      # There is no known scenario today where another actor is changing another user's setting here, but check for equality
      # here just in case so that we don't get confusing data in telemetry.
      previous_value_minutes = codespace_default_idle_timeout if actor.feature_flag_enabled?(:codespaces_hydro_idle_timeout, default: true) && actor == self

      changed = if timeout.nil?
        config.delete(KEY, actor)
      else
        timeout_in_minutes = timeout.to_i.minutes
        raise InvalidCodespaceIdleTimeout if timeout_in_minutes < Codespaces::Vscs::MIN_IDLE_TIME || timeout_in_minutes > Codespaces::Vscs::MAX_IDLE_TIME
        config.set!(KEY, timeout_in_minutes / 1.minute, actor, force)
      end
      return unless changed

      GitHub.dogstats.increment("codespace_default_idle_timeout.updated")
      if actor.feature_flag_enabled?(:codespaces_hydro_idle_timeout, default: true) && actor == self
        GlobalInstrumenter.instrument("codespaces.default_idle_timeout_updated", {
          actor: self,
          value_minutes: timeout&.to_i,
          previous_value_minutes:,
        })
      end
    end
  end
end
