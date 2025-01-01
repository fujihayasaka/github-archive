# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class CopilotSWEAgent

      MAX_SESSION_TIME = T.let(1.hour, Integer)
      NAME = "Copilot SWE Agent"
      SLUG = "copilot-swe-agent"

      sig { returns(T.proc.returns(T.nilable(Integer))) }
      def self.id_finder
        ->() {
          Integration.find_by(
            owner_id: GitHub.first_party_apps_owner_id,
            slug: SLUG,
          )&.id
        }
      end

      PRODUCTION = T.let({
        alias: :copilot_swe_agent,
        id: id_finder,
        inherits: [:first_party],
        capabilities: {
          actions_dynamic_workflows: true,
          can_auto_approve_oauth_authorization: true,
          enforce_internal_access_on_token_generation: false,
          auto_upgrade_permissions: true,
          # This will become true, once we have controls to opt-in/out
          # of the feature at the repo/org level
          installed_globally: false,
          proxima_first_party_sync: true,
          user_installable: true,
          limited_access: false,
          is_copilot: true,
        },
        properties: {
          display_login: "Copilot",
          oauth_access_expiry: MAX_SESSION_TIME,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/copilot-extensibility"],
      }, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String]))

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
      }, T::Hash[Symbol, Symbol])

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        if self.installed?
          return Integration.find_by(
            owner_id: GitHub.first_party_apps_owner_id,
            slug: SLUG
          )
        end

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

      # Similar to id_finder, but avoids instantiating an ActiveRecord object.
      # Installed globally, shouldn't need to check for a specific IntegrationInstallation.
      sig { returns(T::Boolean) }
      def self.installed?
        Integration.where(
          owner_id: GitHub.first_party_apps_owner_id,
          slug: SLUG
        ).exists?
      end
    end
  end
end
