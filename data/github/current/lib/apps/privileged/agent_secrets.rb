# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class AgentSecrets

      PRODUCTION = T.let({
        alias: :agent_secrets,
        database_lookup_attributes: { key: GitHub.agent_secrets_app_key, owner_id: :first_party_apps_owner_id },
        inherits: [],
        capabilities: {
          attribution_only_system_identity: true, # We are only using this app for secret storage
          user_installable: false, # We are only using this app for secret storage
          proxima_first_party_sync: true, # Sync this app with Proxima stamps
        },
        properties: {
          audit_log_secrets_app_name: "agent_secrets",
          secrets_event_subject: "agent",
          proxima_sync_delegate: :DefaultDelegate, # Use the default delegate for Proxima synchronization
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/actions-dispatch"],
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T.any(Symbol, T::Boolean)], T::Array[String])])

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        return if Apps::Privileged.integration(:agent_secrets).present?

        integration_attributes = {
          owner: GitHub.first_party_apps_owner,
          key: GitHub.agent_secrets_app_key,
          name: "Agent Secrets",
          url: "https://github.com",
          visibility: :private_visibility,
          skip_generate_slug: true,
          skip_restrict_names_with_github_validation: true,
        }
        integration = Integration.create!(integration_attributes)

        Apps::Privileged::Registry.instance.reload_caches!

        integration
      end
    end
  end
end
