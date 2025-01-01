# typed: true
# frozen_string_literal: true

module Apps
  class Internal
    class TeamSync
      APP_NAME = "GitHub Team Synchronization"

      def self.id_finder
        ->() {
          Integration.find_by(
            owner_id: GitHub.trusted_apps_owner_id,
            name: APP_NAME,
          )&.id
        }
      end

      PRODUCTION = {
        alias: :team_sync,
        id: id_finder,
        inherits: [:internal],
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
