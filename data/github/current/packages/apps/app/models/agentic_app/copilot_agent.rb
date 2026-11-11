# typed: strict
# frozen_string_literal: true

module AgenticApp
  # GitHub Copilot Agent - the global AI coding agent
  # This is the only global agent (no installation required)
  class CopilotAgent < Apps::Privileged::CopilotSWEAgent
    include ::AgenticApp
    include Singleton

    sig { override.returns(String) }
    def slug
      Apps::Privileged::CopilotSWEAgent::SLUG
    end

    sig { override.returns(String) }
    def display_name
      "Copilot"
    end

    sig { override.returns(String) }
    def doc_url
      "https://gh.io/copilot-coding-agent-docs"
    end

    sig { override.returns(T.nilable(Integration)) }
    def integration
      Apps::Privileged.integration(:copilot_swe_agent)
    end

    sig { override.returns(T.nilable(Integer)) }
    def bot_id
      integration&.bot_id
    end

    sig { override.returns(T::Boolean) }
    def assignable?
      return false unless integration
      Apps::Privileged.capable?(:is_assignable, app: integration)
    end

    sig { override.returns(T::Boolean) }
    def mentionable?
      return false unless integration
      Apps::Privileged.capable?(:pr_autocomplete_mentionable, app: integration)
    end

    sig { override.returns(T::Boolean) }
    def global?
      true
    end

    sig { override.params(target: T.any(User, Organization, Business)).returns(T::Boolean) }
    def installed_for_target?(target)
      # Global agent - always installed
      true
    end

    sig { override.params(target: T.any(User, Organization, Business)).returns(T::Boolean) }
    def can_be_enabled_for?(target)
      true
    end

    sig do
      override.params(
        repo: T.untyped,
        viewer: T.untyped
      ).returns(T::Boolean)
    end
    def enabled_for_repository?(repo, viewer)
      # Global agent - check repository-level enablement
      # This typically checks a feature flag or repository setting
      return false unless integration
      return false unless repo.copilot_swe_agent_enabled?(viewer)
      true
    end

  end
end
