# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class CodeCoverageAgent
      APP_NAME = "Code Coverage Agent"
      APP_ALIAS = :code_coverage_agent
      SLUG = "code-coverage-agent"

      PRODUCTION = T.let({
        alias: APP_ALIAS,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: APP_NAME },
        inherits: [],
        capabilities: {
          actions_dynamic_workflows: true,
          actions_require_workflow_approval: true,
          danger_zone_permitted: false,
          enforce_internal_access_on_token_generation: true,
          coding_agent_job_execution: true,
          installable_on_emus: true,
          installed_globally: true,
          limited_access: false,
          modifies_check_suite_preferences: false,
          proxima_first_party_sync: true,
          skip_tenant_verification_cap: true,
          user_installable: false,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
          searchable_slug: SLUG,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/code-scanning-engine-quality"],
      }, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String]))

      PERMISSIONS = T.let({
        "contents" => :write,
        "metadata" => :read,
        "pull_requests" => :write,
        "workflows" => :write,
      }, T::Hash[String, Symbol])

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        existing_app = Apps::Privileged.integration(APP_ALIAS)
        return existing_app if existing_app.present?

        integration = Integration.create!(
          owner: GitHub.first_party_apps_owner,
          name: APP_NAME,
          slug: SLUG,
          url: "https://github.com/",
          visibility: :public_visibility,
          default_permissions: PERMISSIONS,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
        )

        Apps::Privileged::Registry.instance.reload_caches!

        integration
      end
    end
  end
end
