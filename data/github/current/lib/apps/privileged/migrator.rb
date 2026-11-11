# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class Migrator
      PRODUCTION = {
        alias: :migrator,
        database_lookup_attributes: {
          owner_id: :first_party_apps_owner_id,
          slug: "migration-export-service",
        },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: !Rails.env.development?,
          installed_globally: true,
          proxima_first_party_sync: true,
          user_installable: false,
          limited_access: false,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/migration-tools"],
      }

      PERMISSIONS = {
        "contents" => :read,
        "metadata" => :read,
      }
    end
  end
end
