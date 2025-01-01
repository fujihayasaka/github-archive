# typed: strict
# frozen_string_literal: true

module Apps
  class Internal
    class CopilotPullRequestReviewer
      extend T::Sig

      MAX_SESSION_TIME = T.let(30.minutes, Integer)
      NAME = "Copilot Pull Request Reviewer"
      SLUG = "copilot-pull-request-reviewer"

      sig { returns(T.proc.returns(T.nilable(Integer))) }
      def self.id_finder
        ->() {
          Integration.find_by(
            owner_id: GitHub.trusted_apps_owner_id,
            slug: SLUG,
          )&.id
        }
      end

      PRODUCTION = T.let({
        alias: :copilot_pull_request_reviewer,
        id: id_finder,
        inherits: [:internal],
        capabilities: {
          installed_globally: true,
          proxima_first_party_sync: true,
          user_installable: false,
          limited_access: false,
        },
        properties: {
          oauth_access_expiry: MAX_SESSION_TIME,
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
        return if Apps::Internal.integration(:copilot_pull_request_reviewer).present?

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          name: NAME,
          slug: SLUG,
          url: "https://github.com/",
          public: true,
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
