# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class HelpHub
      APP_NAME = "GitHub Support"
      STAGING_APP_NAME = "GitHub Support (staging)"

      # Please ping owner of https://catalog.githubapp.com/services/helphub when making changes to this
      # configuration.
      PRODUCTION = {
        alias: :help_hub,
        database_lookup_attributes: { user_id: :first_party_apps_owner_id, name: APP_NAME },
        inherits: [:first_party],
        capabilities: {
          can_auto_approve_oauth_authorization: true,
          oauth_authorizations_revocable_by_user: false,
          skip_oauth_organization_credential_authorizations: true,
          proxima_first_party_sync: true,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }

      # Please ping owner of https://catalog.githubapp.com/services/helphub when making changes to this
      # configuration.
      STAGING = {
        alias: :help_hub_staging,
        database_lookup_attributes: { user_id: :first_party_apps_owner_id, name: STAGING_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          can_auto_approve_oauth_authorization: true,
          oauth_authorizations_revocable_by_user: false,
          skip_oauth_organization_credential_authorizations: true,
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
