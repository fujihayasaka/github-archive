# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    # This is solely for testing syncing to proxima and will be
    # removed after testing completes
    # https://github.com/github/ecosystem-apps/issues/4082
    class BastianBalthazar

      APP_NAME = "Bastian Balthazar"
      DOTCOM_OWNER_LOGIN = "apps-team-at-work"

      def self.owner_id
        if GitHub.multi_tenant_enterprise?
          return GitHub.trusted_apps_owner_id
        end

        Organization.unscoped.find_by_login(DOTCOM_OWNER_LOGIN)&.id
      end

      def self.id_finder
        ->() {
          OauthApplication.find_by(
            user: owner_id,
            name: APP_NAME,
          )&.id
        }
      end


      PRODUCTION = {
        alias: :bux,
        id: id_finder,
        inherits: [],
        capabilities: {
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
