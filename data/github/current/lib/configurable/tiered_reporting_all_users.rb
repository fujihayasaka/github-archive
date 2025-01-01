# typed: false
# frozen_string_literal: true

# Configures whether all users can report objectionable content to maintainers
module Configurable
  module TieredReportingAllUsers
    extend Configurable::Async

    KEY = "tiered_reporting_all_users"

    # Enable tiered_reporting_all_users for the repository
    def enable_tiered_reporting_all_users(actor:)
      return if tiered_reporting_all_users_explicitly_enabled?

      config.enable(KEY, actor)

      GlobalInstrumenter.instrument("tiered_reporting_all_users.toggle", {
        repository: self,
        actor: actor,
        owner: owner,
        toggle_state: "ENABLED",
      })
    end

    # Disable tiered_reporting_all_users for the repository
    def disable_tiered_reporting_all_users(actor:)
      return if tiered_reporting_all_users_explicitly_disabled?

      config.disable(KEY, actor)

      GlobalInstrumenter.instrument("tiered_reporting_all_users.toggle", {
        repository: self,
        actor: actor,
        owner: owner,
        toggle_state: "DISABLED",
      })
    end

    # Determine whether tiered_reporting_all_users is explicitly enabled
    def tiered_reporting_all_users_explicitly_enabled?
      config.enabled?(KEY)
    end

    async_configurable :tiered_reporting_all_users_explicitly_enabled?

    # Determine whether tiered_reporting_all_users is explicitly disabled
    def tiered_reporting_all_users_explicitly_disabled?
      config.get(KEY) == false
    end

    # Determine if tiered_reporting_all_users has neither been explicitly set
    # or unset
    def tiered_reporting_all_users_unset?
      config.get(KEY).nil?
    end
  end
end
