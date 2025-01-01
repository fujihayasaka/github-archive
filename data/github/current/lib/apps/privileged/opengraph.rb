# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class OpenGraph
      APP_NAME = "custom-og-image"

      PRODUCTION = {
        alias: :opengraph,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: APP_NAME },
        inherits: [:first_party],
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
        available_on_ghes: false,
      }

    end
  end
end
