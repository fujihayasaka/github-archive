# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class GHN
      OAUTH_APP_NAME = "GHN"

      PRODUCTION = {
        alias: :ghn,
        database_lookup_attributes: { user_id: :first_party_apps_owner_id, name: OAUTH_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          access_internal_graphql_notifications: true,
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
