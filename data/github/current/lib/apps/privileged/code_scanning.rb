# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class CodeScanning
      # We use the same name (although the slug version github-code-scanning) in turboscan. Changes here should be reflected in Turboscan too.
      APP_NAME = "GitHub Advanced Security"
      # fallback to these values during transition
      APP_NAME_OLD = "GitHub Code Scanning"

      def self.id_finder(app_name, app_name_old)
        ->() {
          Integration.find_by(
            owner_id: GitHub.trusted_apps_owner_id,
            name: app_name,
          )&.id || Integration.find_by(
            owner_id: GitHub.trusted_apps_owner_id,
            name: app_name_old,
          )&.id
        }
      end

      PRODUCTION = {
        alias: :code_scanning,
        id: id_finder(APP_NAME, APP_NAME_OLD),
        inherits: [:first_party],
        capabilities: {
          installed_globally: true,
          limited_access: false,
          enforce_internal_access_on_token_generation: false,
          user_installable: false,
          proxima_first_party_sync: true,
          skip_emu_visibility_cap: true,
          skip_emu_ownership_cap: true, # skip CAP policy that ensures EMUs are not taking actions outside of their enterprise,
          bypass_rest_emu_integration_read_protection: true,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/code-scanning-experiences"],
      }

      PERMISSIONS = {
        "actions"              => :read,
        "checks"               => :write,
        "contents"             => :read,
        "metadata"             => :read,
      }

      GHAS_BOT_LOGIN = "github-advanced-security"

      def self.id
        return @code_scanning_id if defined?(@code_scanning_id)
        @code_scanning_id = Apps::Privileged.integration_id(:code_scanning)
      end

      def self.reload_id
        remove_instance_variable(:@code_scanning_id) if defined?(@code_scanning_id)
      end

      def self.seed_database!
        app = Apps::Privileged.integration(:code_scanning)
        if app.present?
          puts "Code scanning app id=#{app.id} name=#{app.name} already exists, skipping..."
          return app
        end

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          name: APP_NAME,
          url: "https://github.com/",
          visibility: :public_visibility,
          default_permissions: PERMISSIONS,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
        }
        app = Integration.create!(integration_attributes)
        puts "Created code scanning app id=#{app.id} name=#{app.name}"

        app
      end

      def self.update_app!(permissions: PERMISSIONS)
        app = Apps::Privileged.integration(:code_scanning)
        return unless app.present?

        if app.name == APP_NAME_OLD
          app.name = APP_NAME
          app.save!
        end

        current_version = app.latest_version
        transient_version = IntegrationVersion.new(
          integration: app,
          default_permissions: permissions,
        )

        diff = IntegrationVersion::Differ.perform(
          old_version: current_version,
          new_version: transient_version
        )

        return if diff.unchanged?

        result = Integration::PermissionsEditor.perform(
          integration: app,
          permissions_and_events: {
            default_permissions: permissions,
          }
        )

        raise result.error unless result.success?
      end
    end
  end
end
