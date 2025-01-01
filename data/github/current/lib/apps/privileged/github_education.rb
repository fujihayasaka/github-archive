# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class GitHubEducation
      APP_NAME = "GitHub Education"
      DEV_APP_NAME = "GitHub Education (development)"
      STAGING_APP_NAME = "GitHub Education (staging)"
      GITHUB_EDUCATION_CLIENT_ID = "de7e3b6548f2ed9bbceb".freeze

      def self.id_finder(name)
        ->() {
          OauthApplication.where(
            user_id: GitHub.first_party_apps_owner_id,
            name: name
          ).pluck(:id).first
        }
      end

      PRODUCTION = {
        alias: :github_education,
        id: id_finder(APP_NAME),
        inherits: [:first_party],
        capabilities: {
          blockable_first_party_client: true,
          can_auto_approve_oauth_authorization: true,
          oauth_authorizations_revocable_by_user: false,
          organization_oauth_app_policy_exempt: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }

      DEVELOPMENT = {
        alias: :github_education_development,
        id: id_finder(DEV_APP_NAME),
        inherits: [:first_party],
        capabilities: {
          blockable_first_party_client: true,
          can_auto_approve_oauth_authorization: true,
          oauth_authorizations_revocable_by_user: false,
          organization_oauth_app_policy_exempt: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }

      STAGING = {
        alias: :github_education_staging,
        id: id_finder(STAGING_APP_NAME),
        inherits: [:first_party],
        capabilities: {
          blockable_first_party_client: true,
          can_auto_approve_oauth_authorization: true,
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
        STAGING,
      ]
    end
  end
end
