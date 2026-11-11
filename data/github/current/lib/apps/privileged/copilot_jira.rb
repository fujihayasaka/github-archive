# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class CopilotJira
      NAME = "GitHub Copilot for Jira"
      COPILOT_JIRA_CLIENT_ID = "Iv23li7XEoCZMEvAxP6C"

      PRODUCTION = T.let({
        alias: :copilot_jira,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, key: COPILOT_JIRA_CLIENT_ID },
        inherits: [],
        capabilities: {
          proxima_first_party_sync: true,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/copilot-discovery"],
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String])])

      # Make sure to make the live changes way ahead of needing the permissions in production (at least 24h ahead)
      # Make sure to update the permissions below to reflect what's updated in the app in production
      PERMISSIONS = T.let({
        contents: :write,
        metadata: :read,
        pull_requests: :write,
        actions: :write,

      }, T::Hash[Symbol, Symbol])

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        existing_app = Apps::Privileged.integration(:copilot_jira)
        return existing_app if existing_app.present?

        integration_attributes = {
          owner: GitHub.first_party_apps_owner,
          name: NAME,
          url: "https://github.com/",
          visibility: :public_visibility,
          default_permissions: PERMISSIONS,
          skip_restrict_names_with_github_validation: true,
        }
        Integration.create!(integration_attributes)
      end
    end
  end
end
