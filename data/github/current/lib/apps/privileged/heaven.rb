# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class Heaven
      APP_NAME = "GitHub Heaven"
      STAGING_APP_NAME = "GitHub Heaven (Staging)"

      PRODUCTION = {
        alias: :github_heaven,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: APP_NAME },
        inherits: [:first_party],
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
        available_on_ghes: false,
      }

      STAGING = {
        alias: :github_heaven_staging,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: STAGING_APP_NAME },
        inherits: [:first_party],
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
        available_on_ghes: false,
      }
    end
  end
end
