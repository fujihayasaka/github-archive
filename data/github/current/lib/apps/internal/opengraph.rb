# typed: true
# frozen_string_literal: true

module Apps
  class Internal
    class OpenGraph
      APP_NAME = "custom-og-image"

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
        alias: :opengraph,
        id: id_finder(APP_NAME),
        inherits: [:internal],
        capabilities: {
          enforce_internal_access_on_token_generation: !Rails.env.development?,
          limited_access: false,
          installed_globally: true,
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
