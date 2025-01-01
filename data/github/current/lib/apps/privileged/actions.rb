# typed: true
# frozen_string_literal: true

require "apps/installation_instrumenter/actions"

module Apps
  class Privileged
    class Actions
      PACKAGES_AUTHORIZATION_NAME = "actions"

      FILE_ADDED_DECISION = ->(opts = {}) {
        return false unless opts[:repo]
        GitHub.actions_enabled?
      }

      PRODUCTION = {
        alias: :actions,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: GitHub.launch_github_app_name },
        inherits: [:first_party],
        capabilities: {
          access_enterprise_actions_token_api: true,
          abuse_limit_multiplier: true, # https://github.com/github/ecosystem-api/issues/1860
          auto_upgrade_permissions: true,
          can_install_on_security_advisory_repos: true, # https://github.com/github/c2c-actions-experience/issues/2474
          can_receive_lightweight_access_token_response: true,
          can_set_loopback_webhook: true,
          # Do not enforce internal access for the local environment, but require it for production.
          enforce_internal_access_on_token_generation: !Rails.env.development?, # https://github.com/github/github/pull/141261
          extend_access_token_expiry: true, # https://github.com/github/ecosystem-apps/issues/792
          follow_repository_transfers: true,
          installed_globally: true,
          ip_allowlist_exempt_for_internal_apis: true,
          limited_access: false,
          manage_packages_permissions: true,
          per_pull_request_permissions: true, # https://github.com/github/ce-engineering/issues/289
          per_repo_rate_limit: true, # https://github.com/github/c2c-actions-experience/issues/1968
          repo_owner_rate_limit: true, # https://github.com/github/actions-launch/issues/350
          resolve_actions: true,
          restricted_modification_of_public_resources: true, # https://github.com/github/ecosystem-apps/issues/581
          skip_version_update: true, # https://github.com/github/actions-launch/issues/384
          skip_version_update_audit_log: true,
          user_installable: false,
          global_app_overrides_rate_limit: true,
          proxima_first_party_sync: true,
          skip_emu_visibility_cap: true,
          skip_emu_ownership_cap: true, # skip CAP policy that ensures EMUs are not taking actions outside of their enterprise,
          bypass_rest_emu_integration_read_protection: true,
          bypass_github_models_user_models_permission: true,
        },
        properties: {
          audit_log_secrets_app_name: "actions",
          secrets_event_subject: "actions",
          hourly_per_repo_rate_limit: 1_000,
          packages_authorization_name: PACKAGES_AUTHORIZATION_NAME,
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {
          "AutomaticAppInstallation::Handlers::FileAdded" => FILE_ADDED_DECISION,
        },
        custom_instrumentation_events: {
          create_installation: ->(installation, configurations) {
            Apps::InstallationInstrumenter::Actions.create_event_details(installation, configurations)
          },
          create_scoped_installation: :skip, # replaces skip_scoped_installation_audit_log for now
          repositories_added: ->(installation, configurations) {
            Apps::InstallationInstrumenter::Actions.repositories_added_event_details(installation, configurations)
          }
        },
        owners: [],
      }

      LAB = {
        alias: :actions_lab,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: GitHub.launch_lab_github_app_name },
        inherits: [:first_party],
        capabilities: {
          access_enterprise_actions_token_api: true,
          actions_dynamic_workflows: true,
          auto_upgrade_permissions: true,
          can_install_on_security_advisory_repos: true,
          can_receive_lightweight_access_token_response: true,
          enforce_internal_access_on_token_generation: true, # https://github.com/github/github/pull/141261
          extend_access_token_expiry: true, # https://github.com/github/ecosystem-apps/issues/792
          follow_repository_transfers: true,
          installed_globally: true,
          ip_allowlist_exempt_for_internal_apis: true,
          limited_access: false,
          manage_packages_permissions: true,
          per_pull_request_permissions: true, # https://github.com/github/ce-engineering/issues/289
          per_repo_rate_limit: true, # https://github.com/github/c2c-actions-experience/issues/1968
          repo_owner_rate_limit: true, # https://github.com/github/actions-launch/issues/350
          resolve_actions: true,
          restricted_modification_of_public_resources: true, # https://github.com/github/ecosystem-apps/issues/581
          skip_version_update: true, # https://github.com/github/actions-launch/issues/384
          skip_version_update_audit_log: true,
          user_installable: false,
          global_app_overrides_rate_limit: true,
          proxima_first_party_sync: false, # Skip syncing the Lab app with Proxima stamps, it's unique to Dotcom
          skip_emu_visibility_cap: true,
          skip_emu_ownership_cap: true, # skip CAP policy that ensures EMUs are not taking actions outside of their enterprise,
          bypass_rest_emu_integration_read_protection: true,
          bypass_github_models_user_models_permission: true,
        },
        properties: {
          audit_log_secrets_app_name: "actions",
          secrets_event_subject: "actions",
          hourly_per_repo_rate_limit: 1_000,
          packages_authorization_name: PACKAGES_AUTHORIZATION_NAME,
        },
        can_auto_install: {
          "AutomaticAppInstallation::Handlers::FileAdded" => FILE_ADDED_DECISION,
        },
        custom_instrumentation_events: {},
        owners: [],
      }

      # TODO: Use the resource registry
      PERMISSIONS = {
        "actions"              => :write,
        "administration"       => :read,
        "attestations"         => :write,
        "checks"               => :write,
        "contents"             => :write,
        "deployments"          => :write,
        "discussions"          => :write,
        "issues"               => :write,
        "metadata"             => :read,
        "merge_queues"         => :write,
        "organization_packages" => :write,
        "packages"             => :write,
        "pages"                => :write,
        "pull_requests"        => :write,
        "repository_hooks"     => :write,
        "repository_projects"  => :write,
        "security_events"      => :write,
        "statuses"             => :write,
        "vulnerability_alerts" => :read,
      }

      def self.seed_database!(app_url:, webhook_url:, webhook_secret:, insecure_ssl:, client_key:, client_secret:, public_key:)
        return if Apps::Privileged.integration_id(:actions, force_database_lookup: true).present?

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          name: GitHub.launch_github_app_name,
          url: app_url,
          key: client_key,
          visibility: :public_visibility,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
          no_repo_permissions_allowed: true,
        }
        app = Integration.create!(integration_attributes)

        Apps::Privileged::Registry.instance.reload_caches!

        app.update!({ hook_attributes: {
          url: webhook_url, secret: webhook_secret, insecure_ssl: insecure_ssl, active: true
        } })

        app.update!({
          default_events: default_events,
          default_permissions: PERMISSIONS
        })

        if public_key.length > 0
          app.public_keys.create!(creator: GitHub.trusted_oauth_apps_owner, skip_generate_key: true, public_pem: public_key)
        end

        app.client_secrets.create!(creator: User.ghost,
          secret_hash: OauthApplicationClientSecret.hash_for(client_secret),
          secret_last_eight: client_secret.last(8))

        create_integration_triggers(app)
        app
      end

      def self.create_integration_triggers(app)
        file_added_trigger_attributes = {
          install_type: "file_added",
          path: '\A\.github/(?:main\.workflow|workflows/[^/]+\.ya?ml)\z',
          reason: "",
          deactivated: false,
          integration_id: app.id,
        }

        IntegrationInstallTrigger.where(integration: app).delete_all
        IntegrationInstallTrigger.create!(file_added_trigger_attributes)
        create_auto_install_trigger(app)
      end

      def self.update_app!(webhook_secret:, client_key:, client_secret:)
        app = GitHub.launch_github_app
        return unless app.present?

        app.hook.remove_disallowed_events
        app.hook.save!

        app.update!({
          key: client_key,
          hook_attributes: {
            secret: webhook_secret,
          },
        })

        app.client_secrets.delete_all
        app.client_secrets.create!(creator: User.ghost,
          secret_hash: OauthApplicationClientSecret.hash_for(client_secret),
          secret_last_eight: client_secret.last(8)
        )

        # Older Actions Apps may not have this newer trigger
        auto_install_trigger = IntegrationInstallTrigger.latest(integration: app, install_type: "actions_automatic_installation")
        if auto_install_trigger.nil?
          create_auto_install_trigger(app)
        end

        old_version = app.latest_version
        transient_version = IntegrationVersion.new(
          integration: app,
          default_events: default_events,
          default_permissions: PERMISSIONS,
        )

        diff = IntegrationVersion::Differ.perform(
          old_version: old_version,
          new_version: transient_version
        )

        return if diff.unchanged?

        # Due to skip_version_update, this won't update the events or permissions for any existng installations
        result = Integration::PermissionsEditor.perform(
          integration: app,
          permissions_and_events: {
            default_events: default_events,
            default_permissions: PERMISSIONS,
          },
        )

        raise result.error unless result.success?
      end

      def self.default_events
        CheckSuite::ActionsDependency::ACTIONS_WEBHOOK_EVENTS - ["security_events"]
      end

      private

      def self.create_auto_install_trigger(app)
        auto_install_trigger_attributes = {
          install_type: "actions_automatic_installation",
          reason: "",
          deactivated: false,
          integration_id: app.id,
        }

        IntegrationInstallTrigger.create!(auto_install_trigger_attributes)
      end
      private_class_method :create_auto_install_trigger
    end
  end
end
