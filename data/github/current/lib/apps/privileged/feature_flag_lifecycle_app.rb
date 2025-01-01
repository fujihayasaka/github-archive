# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class FeatureFlagLifecycleApp
      SLUG = "feature-flag-lifecycle-app".freeze
      def self.id_finder
        ->() {
          Integration.find_by(
            owner_id: GitHub.trusted_apps_owner_id,
            slug: SLUG,
          )&.id
        }
      end

      PRODUCTION = {
        alias: :feature_flag_lifecycle_app,
        id: id_finder,
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
