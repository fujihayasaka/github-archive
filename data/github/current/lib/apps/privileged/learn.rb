# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class Learn
      APP_NAME = "Learn Production"
      STAGING_APP_NAME = "Learn Staging"
      SANDBOX_APP_NAME = "Learn Staging Sandbox"

      PRODUCTION = {
        alias: :learn,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: APP_NAME },
        inherits: [:first_party],
        capabilities: {
          can_auto_approve_oauth_authorization: true,
          oauth_authorizations_revocable_by_user: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/customer-success-engineering"],
        available_on_ghes: false,
      }

      STAGING = {
        alias: :learn_staging,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: STAGING_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          can_auto_approve_oauth_authorization: true,
          oauth_authorizations_revocable_by_user: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/customer-success-engineering"],
        available_on_ghes: false,
      }

      SANDBOX = {
        alias: :github_learn_sandbox,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: SANDBOX_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          can_auto_approve_oauth_authorization: true,
          oauth_authorizations_revocable_by_user: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/customer-success-engineering"],
        available_on_ghes: false,
      }
    end
  end
end
