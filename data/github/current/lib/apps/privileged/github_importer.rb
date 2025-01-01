# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class GitHubImporter
      OAUTH_APP_NAME = "github-importer-production"

      def self.id_finder(name)
        ->() {
          OauthApplication.find_by(
            user_id: GitHub.trusted_apps_owner_id,
            name: name,
          )&.id
        }
      end

      PRODUCTION = {
        alias: :github_importer,
        id: id_finder(OAUTH_APP_NAME),
        inherits: [:first_party],
        capabilities: {
          can_auto_approve_oauth_authorization: true,
          oauth_authorizations_revocable_by_user: false,
          organization_oauth_app_policy_exempt: true,
          saml_sso_required: false,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }
    end
  end
end
