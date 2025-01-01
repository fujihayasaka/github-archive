# typed: true
# frozen_string_literal: true

module Apps
  class Internal
    class Heaven
      APP_NAME = "GitHub Heaven"
      STAGING_APP_NAME = "GitHub Heaven (Staging)"

      def self.id_finder(app_name)
        ->() {
          return nil if GitHub.enterprise?

          Integration.find_by(
            owner_id: GitHub.trusted_apps_owner_id,
            name: app_name,
          )&.id
        }
      end

      PRODUCTION = {
        alias: :github_heaven,
        id: id_finder(APP_NAME),
        inherits: [:internal],
        capabilities: {
          per_repo_rate_limit: true,
          enforce_internal_access_on_token_generation: true,
          proxima_first_party_sync: true,
        },
        properties: {
          hourly_per_repo_rate_limit: 30_000,
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }

      STAGING = {
        alias: :github_heaven_staging,
        id: id_finder(STAGING_APP_NAME),
        inherits: [:internal],
        capabilities: {
          per_repo_rate_limit: true,
          enforce_internal_access_on_token_generation: false,
          proxima_first_party_sync: true,
        },
        properties: {
          hourly_per_repo_rate_limit: 1_000,
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }
    end
  end
end
