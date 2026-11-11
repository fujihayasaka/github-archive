# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class FeatureFlagLifecycleApp
      SLUG = "feature-flag-lifecycle-app".freeze

      PRODUCTION = {
        alias: :feature_flag_lifecycle_app,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, slug: SLUG },
        inherits: [],
        capabilities: {
          proxima_first_party_sync: true,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }
    end
  end
end
