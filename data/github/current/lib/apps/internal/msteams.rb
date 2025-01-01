# typed: true
# frozen_string_literal: true

module Apps
  class Internal
    class Msteams

      def self.id_finder
        ->() {
          Integration.find_by(
            owner_id: GitHub.trusted_apps_owner_id,
            name: GitHub.msteams_github_app_name,
          )&.id
        }
      end

      PRODUCTION = {
        alias: :msteams,
        id: id_finder,
        inherits: [:internal],
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

      STAGING = {
        alias: :msteams_staging,
        id: ->() {
          return nil if GitHub.enterprise?
          # We use an ENV variable here because `id_finder` struggles whenever
          # we try to find an app in the `integrations` org instead of the
          # trusted apps owner. We also do this for the Slack Staging app.
          ENV.fetch("MSTEAMS_STAGING_INTEGRATION_ID", 64753)
        },
        inherits: [:internal],
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
        return if Apps::Internal::Msteams.id_finder.call.present?

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          name: GitHub.msteams_github_app_name,
          url: app_url,
          key: client_key,
          public: true,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
          no_repo_permissions_allowed: true,
          user_token_expiration_enabled: false,
          application_callback_urls_attributes: [{ url: callback_url }],
        }
        app = Integration.create!(integration_attributes)

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

        app.destroy!
      end
    end
  end
end
