# typed: strict
# frozen_string_literal: true

module Apps
  class Internal
    class CopilotChat
      extend T::Sig

      APP_NAME = "Copilot Chat App"
      APP_ALIAS = :copilot_chat
      MAX_SESSION_TIME = T.let(30.minutes, Integer)
      MAX_REFRESH_TIME = T.let(1.day, Integer)

      sig { returns(T.proc.returns(T.nilable(Integer))) }
      def self.integration_id_finder
        ->() {
          Integration.find_by(
            name: APP_NAME,
            owner_id: GitHub.trusted_apps_owner_id
          )&.id
        }
      end

      PRODUCTION = T.let({
        id: integration_id_finder,
        alias: APP_ALIAS,
        inherits: [:internal],
        capabilities: {
          installed_globally: true,
          proxima_first_party_sync: true,
          user_installable: false,
          auto_upgrade_permissions: true,
          can_auto_approve_oauth_authorization: true,
          enforce_internal_access_on_token_generation: true,
          list_current_user_accessible_knowledge_bases: true,
          administer_knowledge_base: true,
          limited_access: false,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
          oauth_access_expiry: MAX_SESSION_TIME,
          refresh_token_expiry: MAX_REFRESH_TIME,
        },
        owners: ["@github/ai-core-dx-reviewers"],
        # NOTE: these are required and expected to be hashes
        can_auto_install: {},
        custom_instrumentation_events: {},
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String])])

      PERMISSIONS = T.let({
        actions: :read,
        checks: :read,
        contents: :read,
        discussions: :read,
        issues: :read,
        metadata: :read,
        members: :read,
        pull_requests: :read,
        statuses: :read,
        knowledge_bases: :read,
      }, T::Hash[Symbol, Symbol])

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        return if Apps::Internal.integration(APP_ALIAS).present?

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          name: APP_NAME,
          url: "https://github.com",
          public: true,
          default_permissions: PERMISSIONS,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
        }

        # NOTE: we only need to hard-code the app ID for development
        # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        if Rails.env.development?
          integration_attributes[:id] = 835
        end

        Integration.create!(integration_attributes)
      end
    end
  end
end
