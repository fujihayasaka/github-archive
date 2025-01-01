# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class TeamSync
      APP_NAME = "GitHub Team Synchronization"

      PRODUCTION = {
        alias: :team_sync,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: APP_NAME },
        inherits: [:first_party],
        capabilities: {
          abuse_limit_multiplier: true,
          auto_upgrade_permissions: true,
          bypass_permission_check_for_team_sync_enterprise: true,
          enforce_internal_access_on_token_generation: false,
          user_installable: false,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }
    end
  end
end
