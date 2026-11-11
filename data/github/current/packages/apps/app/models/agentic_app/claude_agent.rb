# typed: strict
# frozen_string_literal: true

module AgenticApp
  # Claude Agent - Partner AI coding agent requiring installation
  # This agent requires explicit IntegrationInstallation per repository/organization
  class ClaudeAgent < Base
    sig { override.returns(String) }
    def slug
      Apps::Privileged::ClaudeAgent::SLUG
    end

    sig { override.returns(String) }
    def display_name
      "Claude"
    end

    sig { override.returns(String) }
    def display_owner
      "Anthropic"
    end

    sig { override.returns(String) }
    def doc_url
      "https://docs.github.com/en/copilot/responsible-use/copilot-coding-agent"
    end

    sig { override.returns(Symbol) }
    def privileged_app_alias
      :claude_agent
    end

    sig { override.returns(Symbol) }
    def disallow_feature_flag
      :agentshq_disallow_claude
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
