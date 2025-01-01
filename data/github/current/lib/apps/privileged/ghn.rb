# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class GHN
      OAUTH_APP_NAME = "GHN"

      def self.id_finder(name)
        ->() {
          return nil if GitHub.enterprise?

          OauthApplication.find_by(
            user_id: GitHub.trusted_apps_owner_id,
            name: name,
          )&.id
        }
      end

      PRODUCTION = {
        alias: :ghn,
        id: id_finder(OAUTH_APP_NAME),
        inherits: [:first_party],
        capabilities: {
          access_internal_graphql_notifications: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }
    end
  end
end
