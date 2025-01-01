# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class Dependabot
      ACCESSIBLE_TARGETS = if GitHub.single_or_multi_tenant_enterprise?
        { "github-enterprise" => [] }
      else
        {
          "dsp-testing" => [],
          "feelepxyz" => [],
          "github" => [],
          "jurre" => [],
          "du-global-testing" => []
        }
      end

      PRODUCTION = {
        alias: :dependabot,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, slug: GitHub.dependabot_github_app_slug },
        inherits: [:first_party],
        capabilities: {
          abuse_limit_multiplier: true,
          actions_dynamic_workflows: true,
          actions_require_workflow_approval: false, # Dependabot should be able to trigger workflows (we have separate security controls in place for it)
          auto_upgrade_permissions: true,
          can_install_on_security_advisory_repos: true,
          can_receive_lightweight_access_token_response: true,
          can_set_loopback_webhook: true, # Loopback is used on GHES
          create_permissionless_installation_token: GitHub.enterprise?,
          enforce_internal_access_on_token_generation: true, # https://github.com/github/github/pull/147001
          follow_repository_transfers: true,
          installed_globally: true,
          ip_allowlist_exempt: true,
          proxima_first_party_sync: true,
          skip_stacks_websocket_updates: true,
          skip_version_update_audit_log: true,
          user_installable: false,
          skip_emu_visibility_cap: true,
          skip_emu_ownership_cap: true, # skip CAP policy that ensures EMUs are not taking actions outside of their enterprise
          bypass_rest_emu_integration_read_protection: true,
        },
        properties: {
          accessible_targets: ACCESSIBLE_TARGETS,
          audit_log_secrets_app_name: "dependabot",
          secrets_event_subject: "integration",
          proxima_sync_delegate: :DependabotDelegate,
          proxima_url_templating_hostname: "githubapp.com",
        },
        can_auto_install: {
          "AutomaticAppInstallation::Handlers::FileAdded" => ->(opts = {}) {
            return false unless opts[:repo]
            return false unless honoring_config_file?(opts[:repo])
            GitHub.dependabot_enabled?
          },
        },
        custom_instrumentation_events: {},
        owners: ["@github/dependabot-updates-reviewers"],
      }

      # Staging app is used for testing and development purposes, and should mimic
      # the production app as closely as possible unless config changes are being
      # tested.
      STAGING = {
        **PRODUCTION,
        alias: :dependabot_staging,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, slug: GitHub.dependabot_staging_github_app_slug },
        can_auto_install: {},
      }

      PERMISSIONS = {
        "checks"               => :write,
        "contents"             => :write,
        "issues"               => :write,
        "members"              => :read,
        "metadata"             => :read,
        "pull_requests"        => :write,
        "statuses"             => :read,
        "workflows"            => :write,
        "actions"              => :write,
        "vulnerability_alerts" => :read,
      }

      WEBHOOK_EVENTS = %w[
        check_suite
        issue_comment
        label
        pull_request
        pull_request_review
        pull_request_review_comment
        repository
      ]
      # TODO handle workflow_run events and errors in GitHub cloud
      WEBHOOK_EVENTS.push("workflow_run") if GitHub.enterprise?

      INTEGRATION_TRIGGERS = [
        { install_type: :automatic_security_updates_initialized },
        { install_type: :button_clicked },
        { install_type: :dependabot_repository_access_updated },
        { install_type: :dependency_graph_initialized },
        { install_type: :dependency_update_requested },
        { install_type: :file_added, path: ::Dependabot::CONFIG_FILE_PATH_PATTERN },
        { install_type: :pending_dependabot_installation_requested },
        { install_type: :dependabot_jit_access_requested },
      ]

      def self.seed_database!(app_url:, webhook_url:, webhook_secret:, insecure_ssl:, public_key:)
        return if Apps::Privileged.integration(:dependabot).present?

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          name: GitHub.dependabot_github_app_name,
          slug: GitHub.dependabot_github_app_slug,
          url: app_url,
          visibility: :private_visibility,
          skip_generate_slug: true,
          skip_restrict_names_with_github_validation: true,
          skip_slug_owner_check: true,
          no_repo_permissions_allowed: true,
        }
        app = Integration.create!(integration_attributes)

        Apps::Privileged::Registry.instance.reload_caches!

        app.update!({ hook_attributes: {
          url: webhook_url, secret: webhook_secret, insecure_ssl: insecure_ssl, active: true
        } })

        app.update!({
          default_events: WEBHOOK_EVENTS,
          default_permissions: PERMISSIONS
        })

        if public_key.length > 0
          app.public_keys.create!(creator: GitHub.trusted_oauth_apps_owner, skip_generate_key: true, public_pem: public_key)
        end

        create_integration_triggers(app, force: true)

        app
      end

      def self.update_app!(webhook_url:)
        app = Integration.find_by!(slug: GitHub.dependabot_github_app_slug)
        return unless app.present?

        app.update!({ hook_attributes: { url: webhook_url } })

        old_version = app.latest_version
        transient_version = IntegrationVersion.new(
          integration: app,
          default_events: WEBHOOK_EVENTS,
          default_permissions: PERMISSIONS,
        )

        diff = IntegrationVersion::Differ.perform(
          old_version: old_version,
          new_version: transient_version
        )

        return app if diff.unchanged?

        result = Integration::PermissionsEditor.perform(
          integration: app,
          permissions_and_events: {
            default_events: WEBHOOK_EVENTS,
            default_permissions: PERMISSIONS,
          },
        )

        raise result.error unless result.success?

        create_integration_triggers(app)

        app
      end

      def self.create_integration_triggers(app, force: false)
        IntegrationInstallTrigger.where(integration: app).delete_all if force

        INTEGRATION_TRIGGERS.each do |integration|
          install_type = integration[:install_type]
          next if IntegrationInstallTrigger.latest(integration: app, install_type:).present?

          IntegrationInstallTrigger.create!({
            install_type:,
            path: integration[:path] || "",
            reason: "",
            deactivated: false,
            integration_id: app.id,
          })
        end
      end

      def self.honoring_config_file?(repository)
        SecurityProduct::DependabotConfigFile.new(repository).enabled?
      end
    end
  end
end
