# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class CopilotSWEAgent

      MAX_SESSION_TIME = T.let(1.hour, Integer)
      NAME = "Copilot SWE Agent"
      SLUG = "copilot-swe-agent"

      PRODUCTION = T.let({
        alias: :copilot_swe_agent,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: NAME },
        inherits: [:first_party],
        capabilities: {
          actions_dynamic_workflows: true,
          actions_require_workflow_approval: true,
          can_auto_approve_oauth_authorization: true,
          enforce_internal_access_on_token_generation: false,
          auto_upgrade_permissions: true,
          installed_globally: true,
          proxima_first_party_sync: false,
          user_installable: false,
          limited_access: false,
          is_copilot: true,
          pr_autocomplete_mentionable_as_author: true,
          is_assignable: true,
          ip_allowlist_exempt: true,
        },
        properties: {
          display_login: "Copilot",
          oauth_access_expiry: MAX_SESSION_TIME,
          searchable_slug: SLUG,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/copilot-extensibility"],
      }, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String]))

      # Since the application is a global app, you will need a manager of the app
      # on the GitHub organization to make live changes to the permissions.
      # Make sure to make the live changes way ahead of needing the permissions in production (at least 24h ahead)
      # Make sure to update the permissions below to reflect what's updated in the global app in production
      #
      # If no manager of the app is available, you can request it via a github/security-iam issue (#ce-apps)
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

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        existing_app = Apps::Privileged.integration(:copilot_swe_agent)
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
        Integration.create!(integration_attributes)
      end
    end
  end
end
