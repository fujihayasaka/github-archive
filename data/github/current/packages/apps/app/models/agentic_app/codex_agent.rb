# typed: strict
# frozen_string_literal: true

module AgenticApp
  # Codex Agent - Partner AI coding agent requiring installation
  # This agent requires explicit IntegrationInstallation per repository/organization
  class CodexAgent < Base
    sig { override.returns(String) }
    def slug
      Apps::Privileged::CodexAgent::SLUG
    end

    sig { override.returns(String) }
    def display_name
      "Codex"
    end

    sig { override.returns(String) }
    def display_owner
      "OpenAI"
    end

    sig { override.returns(String) }
    def doc_url
      "https://docs.github.com/en/enterprise-cloud@latest/copilot/concepts/agents/openai-codex"
    end

    sig { override.returns(Symbol) }
    def privileged_app_alias
      :codex_agent
    end

    sig { override.returns(Symbol) }
    def disallow_feature_flag
      :agentshq_disallow_codex
    end

    sig { override.returns(Symbol) }
    def policy_feature_flag
      :agentshq_policy
    end

    sig { override.returns(T::Boolean) }
    def partner_agent?
      true
    end
  end
end
