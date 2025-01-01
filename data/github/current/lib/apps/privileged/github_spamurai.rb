# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class GitHubSpamurai
      OAUTH_APP_NAME = "GitHub Spamurai Next"
      OAUTH_APP_NAME_STAGING = "GitHub Spamurai Next Staging"
      OAUTH_APP_NAME_REMIX = "GitHub Spamurai Next Remix"
      OAUTH_APP_NAME_DEV = "GitHub Spamurai Next Dev"

      PRODUCTION = {
        alias: :github_spamurai_next,
        database_lookup_attributes: { user_id: :first_party_apps_owner_id, name: OAUTH_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          can_auto_approve_oauth_authorization: true, # https://github.com/github/ecosystem-apps/issues/472
          ip_allowlist_exempt: true,
          oauth_authorizations_revocable_by_user: false,
          organization_oauth_app_policy_exempt: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }

      STAGING = {
        alias: :github_spamurai_staging,
        database_lookup_attributes: { user_id: :first_party_apps_owner_id, name: OAUTH_APP_NAME_STAGING },
        inherits: [:first_party],
        capabilities: {
          can_auto_approve_oauth_authorization: true, # https://github.com/github/ecosystem-apps/issues/472
          ip_allowlist_exempt: true,
          oauth_authorizations_revocable_by_user: false,
          organization_oauth_app_policy_exempt: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }

      REMIX = {
        alias: :github_spamurai_remix,
        database_lookup_attributes: { user_id: :first_party_apps_owner_id, name: OAUTH_APP_NAME_REMIX },
        inherits: [:first_party],
        capabilities: {
          can_auto_approve_oauth_authorization: true, # https://github.com/github/ecosystem-apps/issues/472
          ip_allowlist_exempt: true,
          oauth_authorizations_revocable_by_user: false,
          organization_oauth_app_policy_exempt: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }

      DEV = {
        alias: :github_spamurai_dev,
        database_lookup_attributes: { user_id: :first_party_apps_owner_id, name: OAUTH_APP_NAME_DEV },
        inherits: [:first_party],
        capabilities: {
          can_auto_approve_oauth_authorization: true, # https://github.com/github/ecosystem-apps/issues/472
          ip_allowlist_exempt: true,
          oauth_authorizations_revocable_by_user: false,
          organization_oauth_app_policy_exempt: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }
    end
  end
end
