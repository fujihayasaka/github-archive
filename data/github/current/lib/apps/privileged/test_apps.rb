# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class TestApps
      APP_NAME = "Fernando Ferdinand"
      APP_ALIAS = :test_fernando_ferdinand

      # Test app used to verify Proxima sync changes in a production
      # environment without having to rely on a marketplace listing.
      PRODUCTION = {
        alias: APP_ALIAS,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: APP_NAME },
        inherits: [],
        capabilities: {
          proxima_first_party_sync: true
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/authorization-platform"],
      }
    end
  end
end
