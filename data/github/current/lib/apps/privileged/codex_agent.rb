# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class CodexAgent

      MAX_SESSION_TIME = T.let(1.hour, Integer)
      NAME = "openai code agent"
      SLUG = "openai-code-agent"
      LEGACY_APP_CLIENT_ID = "Iv23liVemv8A9if9v0F2"

      PRODUCTION = T.let({
        alias: :codex_agent,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, slug: SLUG },
        inherits: [:agent],
        capabilities: {},
        properties: {
          display_login: "Codex",
          oauth_access_expiry: MAX_SESSION_TIME,
          searchable_slug: SLUG,
          proxima_sync_delegate: :DefaultDelegate,
          oauth_access_limit: 100,
          # This app uses the same mention "@Codex" as the non-privileged OpenAI owned app
          conflicting_client_ids: [LEGACY_APP_CLIENT_ID]
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/copilot-agents"],
      }, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String]))

      # Since the application is a privileged app, you will need a manager of the app
      # on the GitHub organization to make live changes to the permissions.
      # Make sure to make the live changes way ahead of needing the permissions in production (at least 24h ahead)
      # Make sure to update the permissions below to reflect what's updated in the privileged app in production
      #
      # If no manager of the app is available, you can request it via a github/security-iam issue (#authorization)
      PERMISSIONS = T.let({
        contents: :write,
        members: :read,
        metadata: :read,
        pull_requests: :write,
        issues: :write,
        discussions: :write,
        workflows: :write,
        actions: :write,
        environments: :write,
        secrets: :read,
        actions_variables: :read,
        administration: :read,
        checks: :read,
      }, T::Hash[Symbol, Symbol])

      INTEGRATION_TRIGGERS = T.let([
        { install_type: :third_party_agents_enabled },
      ], T::Array[T::Hash[T.untyped, T.untyped]])

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        existing_app = Apps::Privileged.integration(:codex_agent)
        return existing_app if existing_app.present?

        integration_attributes = {
          owner: GitHub.first_party_apps_owner,
          name: NAME,
          slug: SLUG,
          url: "https://github.com/",
          visibility: :public_visibility,
          default_permissions: PERMISSIONS,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
        }
        app = Integration.create!(integration_attributes)
        create_integration_triggers(app, force: true)
        app
      end

      sig { params(app: T.untyped, force: T.untyped).returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
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
    end
  end
end
