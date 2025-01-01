# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class Pages
      INTEGRATION_NAME = "GitHub Pages"
      OAUTH_APP_NAME = "GitHub Pages"

      INTEGRATION = {
        alias: :pages,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: INTEGRATION_NAME },
        inherits: [:first_party],
        capabilities: {
          auto_upgrade_permissions: true,
          enforce_internal_access_on_token_generation: false,
          ip_allowlist_exempt: true,
          oauth_authorizations_revocable_by_user: false,
          proxima_first_party_sync: true,
          user_installable: false,
          skip_emu_visibility_cap: true,
          skip_emu_ownership_cap: true, # skip CAP policy that ensures EMUs are not taking actions outside of their enterprise
          bypass_rest_emu_integration_read_protection: true,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }

      OAUTH = {
        alias: :pages_oauth,
        database_lookup_attributes: { user_id: :first_party_apps_owner_id, name: OAUTH_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          can_auto_approve_oauth_authorization: true,
          oauth_authorizations_revocable_by_user: false,
          organization_oauth_app_policy_exempt: true,
          proxima_first_party_sync: true,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }
    end
  end
end
