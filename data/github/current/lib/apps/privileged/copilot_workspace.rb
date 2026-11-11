# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class CopilotWorkspace

      APP_NAME = "Copilot Workspace (production)"
      APP_ALIAS = :copilot_workspace
      MAX_SESSION_TIME = T.let(30.minutes, Integer)
      MAX_REFRESH_TIME = T.let(1.day, Integer)

      PRODUCTION = T.let({
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: APP_NAME },
        alias: APP_ALIAS,
        inherits: [:first_party],
        capabilities: {
          installed_globally: true,
          proxima_first_party_sync: true,
          user_installable: false,
          can_auto_approve_oauth_authorization: true,
          enforce_internal_access_on_token_generation: true,
          list_current_user_accessible_knowledge_bases: true,
          administer_knowledge_base: true,
          limited_access: true,
          generate_copilot_cdn_token: true,
          access_codespaces: true,
        },
        properties: {
          accessible_targets: { "github" => %w(blackbird copilot-api) }, # Limits site-scoped integration installations (Global app) tokens to only the configured targets and repos.
          proxima_sync_delegate: :DefaultDelegate,
          oauth_access_expiry: MAX_SESSION_TIME,
          refresh_token_expiry: MAX_REFRESH_TIME,
        },
        owners: ["@github/ai-core-dx-reviewers"],
        # NOTE: these are required and expected to be hashes
        can_auto_install: {},
        custom_instrumentation_events: {
          create_installation: :skip,
          create_scoped_installation: :skip,
        },
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String])])

      # NOTE: These are only used for database seeding!
      # If you want to influence the real permissions, edit them on the Global App at:
      #   https://github.com/organizations/github/settings/apps/copilot-workspace-production/permissions
      PERMISSIONS = T.let({
        actions: :read,
        checks: :read,
        codespaces: :write,
        contents: :write,
        discussions: :read,
        issues: :read,
        metadata: :read,
        members: :read,
        pull_requests: :write,
        statuses: :read,
        knowledge_bases: :read,
      }, T::Hash[Symbol, Symbol])

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        return if Apps::Privileged.integration(APP_ALIAS).present?

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          name: APP_NAME,
          url: "https://github.com",
          visibility: :public_visibility,
          default_permissions: PERMISSIONS,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
        }

        app = Integration.create!(integration_attributes)
        Apps::Privileged::Registry.instance.reload_caches!
        app
      end
    end
  end
end
