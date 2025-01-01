# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class Classroom
      APP_NAME = "GitHub Classroom"
      STAGING_APP_NAME = "GitHub Classroom (Staging)"
      GITHUB_CLASSROOM = "64a051cf1598b9f0658f".freeze

      def self.id_finder(app_name)
        ->() {
          return nil if GitHub.enterprise?

          Integration.find_by(
            owner_id: GitHub.trusted_apps_owner_id,
            name: app_name,
          )&.id
        }
      end

      PRODUCTION = {
        alias: :github_classroom,
        id: id_finder(APP_NAME),
        inherits: [:first_party],
        capabilities: {
          auto_upgrade_permissions: true,
          enforce_internal_access_on_token_generation: true,
          ip_allowlist_exempt: true,
          skip_version_update_audit_log: true,
          user_installable: false,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {
          create_installation: :skip, # replaces skip_installation_creation_audit_log for now
          create_scoped_installation: :skip, # replaces skip_scoped_installation_audit_log for now
        },
        owners: [],
      }

      STAGING = {
        alias: :github_classroom_staging,
        id: id_finder(STAGING_APP_NAME),
        inherits: [:first_party],
        capabilities: {
          auto_upgrade_permissions: true,
          enforce_internal_access_on_token_generation: true,
          ip_allowlist_exempt: true,
          skip_version_update_audit_log: true,
          user_installable: false,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {
          create_installation: :skip, # replaces skip_installation_creation_audit_log for now
          create_scoped_installation: :skip, # replaces skip_scoped_installation_audit_log for now
        },
        owners: [],
      }
    end
  end
end
