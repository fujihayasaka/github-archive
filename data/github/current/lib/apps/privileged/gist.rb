# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class Gist
      OAUTH_APP_NAME = "Gist"
      DEV_OAUTH_APP_NAME = "Gist (dev)"
      ENTERPRISE_OAUTH_APP_NAME = "GitHub Gist"

      def self.production_id_finder
        ->() {
          app_name = GitHub.enterprise? ? ENTERPRISE_OAUTH_APP_NAME : OAUTH_APP_NAME

          OauthApplication.find_by(
            user_id: GitHub.first_party_apps_owner_id,
            name: app_name,
            key: GitHub.gist_oauth_client_id
          )&.id
        }
      end

      PRODUCTION = {
        alias: :gist,
        id: production_id_finder,
        inherits: [:first_party],
        capabilities: {
          can_auto_approve_oauth_authorization: true, # https://github.com/github/ecosystem-apps/issues/472
          oauth_authorizations_revocable_by_user: false,
          organization_oauth_app_policy_exempt: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }

      DEVELOPMENT = {
        alias: :gist_dev,
        id: ->() {
          OauthApplication.find_by(
            user_id: GitHub.first_party_apps_owner_id,
            name: DEV_OAUTH_APP_NAME
          )&.id
        },
        inherits: [:first_party],
        capabilities: {
          can_auto_approve_oauth_authorization: true, # https://github.com/github/ecosystem-apps/issues/472
          oauth_authorizations_revocable_by_user: false,
          organization_oauth_app_policy_exempt: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }

      OAUTH_APPS = [
        PRODUCTION,
        DEVELOPMENT,
      ]

    end
  end
end
