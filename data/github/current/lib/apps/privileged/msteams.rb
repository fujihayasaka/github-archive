# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class Msteams

      PRODUCTION = {
        alias: :msteams,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: GitHub.msteams_github_app_name },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
          ip_allowlist_exempt: true,
          access_internal_reminders_api: true,
          access_graphql_discussion_comment_url: true,
          scheduled_reminders_user_scoped_setup: true,
          can_set_loopback_webhook: GitHub.enterprise?, # Loopback is used in GHES
          proxima_first_party_sync: true,
        },
        properties: {
          scheduled_reminders_feature_flag: "scheduled_reminders_ms_teams",
          scheduled_reminders_workspace_class: "ReminderTeamsWorkspace",
          scheduled_reminders_workspace_type_id_attribute: "teams_id",
          allowed_internal_events: [:reminder],
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/notifications"],
      }

      STAGING_ID = 64753
      STAGING = {
        alias: :msteams_staging,
        database_lookup_attributes: { id: ENV.fetch("MSTEAMS_STAGING_INTEGRATION_ID", STAGING_ID) },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
          ip_allowlist_exempt: true,
          access_internal_reminders_api: true,
          access_graphql_discussion_comment_url: true,
          scheduled_reminders_user_scoped_setup: true,
        },
        properties: {
          scheduled_reminders_feature_flag: "scheduled_reminders_ms_teams",
          scheduled_reminders_workspace_class: "ReminderTeamsWorkspace",
          scheduled_reminders_workspace_type_id_attribute: "teams_id",
          allowed_internal_events: [:reminder],
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/notifications"],
        available_on_ghes: false,
      }

      PERMISSIONS = {
        "actions"              => :write,
        "checks"               => :read,
        "contents"             => :read,
        "deployments"          => :read,
        "discussions"          => :read,
        "issues"               => :write,
        "metadata"             => :read,
        "members"              => :read,
        "pull_requests"        => :write,
        "statuses"             => :read,
      }

      WEBHOOK_EVENTS = %w[
        check_run
        check_suite
        commit_comment
        create
        delete
        deployment
        deployment_review
        deployment_status
        discussion
        discussion_comment
        issues
        issue_comment
        milestone
        public
        pull_request
        pull_request_review
        pull_request_review_comment
        push
        release
        reminder
        repository
        repository_dispatch
        status
        workflow_run
        workflow_job
      ]

      def self.seed_database!(app_url:, webhook_url:, callback_url:, webhook_secret:, insecure_ssl:, client_key:, client_secret:, public_key:)
        return if Apps::Privileged.integration_id(:msteams, force_database_lookup: true).present?

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          name: GitHub.msteams_github_app_name,
          url: app_url,
          key: client_key,
          visibility: :public_visibility,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
          no_repo_permissions_allowed: true,
          user_token_expiration_enabled: false,
          application_callback_urls_attributes: [{ url: callback_url }],
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

        app.client_secrets.create!(creator: User.ghost,
          secret_hash: OauthApplicationClientSecret.hash_for(client_secret),
          secret_last_eight: client_secret.last(8))

        app
      end

      def self.update_app!(app_url:, webhook_url:, callback_url:, webhook_secret:, insecure_ssl:, client_key:, client_secret:, public_key:)
        app = GitHub.msteams_github_app

        return unless app.present?

        app.update!({
          url: app_url,
          key: client_key,
          hook_attributes: {
            url: webhook_url, secret: webhook_secret, insecure_ssl: insecure_ssl
          },
        })

        unless app.callback_url_direct_match?(callback_url)
          app.application_callback_urls.delete_all
          app.update!(application_callback_urls_attributes: [{ url: callback_url }])
        end

        app.public_keys.delete_all
        app.public_keys.create!(creator: GitHub.trusted_oauth_apps_owner, skip_generate_key: true, public_pem: public_key)

        app.client_secrets.delete_all
        app.client_secrets.create!(creator: User.ghost,
          secret_hash: OauthApplicationClientSecret.hash_for(client_secret),
          secret_last_eight: client_secret.last(8)
        )

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

        return if diff.unchanged?

        Integration::PermissionsEditor.perform(
          integration: app,
          permissions_and_events: {
            default_events: WEBHOOK_EVENTS,
            default_permissions: PERMISSIONS,
          },
        )
      end

      def self.delete_app!
        app = GitHub.msteams_github_app

        return unless app.present?

        result = app.destroy!
        Apps::Privileged::Registry.instance.reload_caches!
        result
      end
    end
  end
end
