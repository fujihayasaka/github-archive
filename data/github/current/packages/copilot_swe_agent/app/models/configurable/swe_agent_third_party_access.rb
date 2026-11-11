# typed: strict
# frozen_string_literal: true

# Manage whether Copilot coding agent can use third party services like Anthropic Claude or OpenAI Codex
module Configurable
  module SweAgentThirdPartyAccess
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }
    requires_ancestor { GitHub::VexiActor }

    KEY = "swe_agent_third_party_access"

    sig { params(actor: User, force: T::Boolean).void }
    def enable_swe_agent_third_party_access(actor:, force: false)
      changed = config.enable!(KEY, actor, force)
      return unless changed

      GitHub.dogstats.increment("swe_agent_third_party_access.enable", tags: ["actor_type:User"])
    end

    sig { params(actor: User).void }
    def disable_swe_agent_third_party_access(actor:)
      changed = config.delete(KEY, actor)
      return unless changed

      GitHub.dogstats.increment("swe_agent_third_party_access.disable", tags: ["actor_type:User"])
    end

    sig { params(agent: T.nilable(AgenticApp)).returns(T::Boolean) }
    def swe_agent_third_party_access_enabled?(agent: nil)
      # This is temporary to ensure that enabled_for_repository? works for the Agentic App when the FF is enabled
      if agent && self.feature_flag_enabled?(:agentshq_per_app_agents, default: false)
        target = T.cast(self, T.any(User, Organization, Business))
        agent.installed_for_target?(target)
      else
        T.bind(self, Configurable)
        config.enabled?(KEY)
      end
    end
  end
end
