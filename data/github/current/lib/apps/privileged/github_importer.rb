# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class GitHubImporter
      OAUTH_APP_NAME = "github-importer-production"

      PRODUCTION = {
        alias: :github_importer,
        database_lookup_attributes: { user_id: :first_party_apps_owner_id, name: OAUTH_APP_NAME },
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
