# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class CopilotPullRequestReviewer

      MAX_SESSION_TIME = T.let(30.minutes, Integer)
      NAME = "Copilot Pull Request Reviewer"
      SLUG = "copilot-pull-request-reviewer"

      PRODUCTION = T.let({
        alias: :copilot_pull_request_reviewer,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: NAME },
        inherits: [:first_party],
        capabilities: {
          installed_globally: true,
          proxima_first_party_sync: true,
          user_installable: false,
          limited_access: false,
          is_copilot: true,
          actions_require_workflow_approval: true,
        },
        properties: {
          display_login: "Copilot",
          oauth_access_expiry: MAX_SESSION_TIME,
          searchable_slug: SLUG,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/pull-requests"],
      }, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String]))

      PERMISSIONS = T.let({
        contents: :read,
        members: :read,
        metadata: :read,
        pull_requests: :write,
      }, T::Hash[Symbol, Symbol])

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        return if Apps::Privileged.integration(:copilot_pull_request_reviewer).present?

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          name: NAME,
          slug: SLUG,
          url: "https://github.com/",
          visibility: :public_visibility,
          default_permissions: PERMISSIONS,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
        }

        # NOTE: we only need to hard-code the app ID for development
        # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        if Rails.env.development?
          integration_attributes[:id] = 836
        end

        Integration.create!(integration_attributes)
      end
    end
  end
end
