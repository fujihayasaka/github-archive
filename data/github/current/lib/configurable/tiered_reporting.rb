# typed: false
# frozen_string_literal: true

# Configures whether contributors to a repo can report objectionable content to maintainers
module Configurable
  module TieredReporting
    extend Configurable::Async

    KEY = "tiered_reporting"

    # Enable tiered_reporting for the repository
    def enable_tiered_reporting(actor:, instrument: true)
      return if tiered_reporting_explicitly_enabled?

      config.enable(KEY, actor)

      if instrument
        GlobalInstrumenter.instrument("tiered_reporting.toggle", {
          repository: self,
          actor: actor,
          owner: owner,
          toggle_state: "ENABLED",
        })
      end
    end

    # Disable tiered reporting for the repository
    def disable_tiered_reporting(actor:)
      return if tiered_reporting_explicitly_disabled?

      config.disable(KEY, actor)

      GlobalInstrumenter.instrument("tiered_reporting.toggle", {
        repository: self,
        actor: actor,
        owner: owner,
        toggle_state: "DISABLED",
      })
    end

    # Determine whether tiered reporting is explicitly enabled
    def tiered_reporting_explicitly_enabled?
      config.enabled?(KEY)
    end

    async_configurable :tiered_reporting_explicitly_enabled?

    # Determine whether tiered reporting is explicitly disabled
    def tiered_reporting_explicitly_disabled?
      config.get(KEY) == false
    end

    # Determine if tiered reporting has neither been explicitly set
    # or unset
    def tiered_reporting_unset?
      config.get(KEY).nil?
    end
  end
end
