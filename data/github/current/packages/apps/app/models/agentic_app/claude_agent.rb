# typed: strict
# frozen_string_literal: true

module AgenticApp
  # Claude Agent - Partner AI coding agent requiring installation
  # This agent requires explicit IntegrationInstallation per repository/organization
  class ClaudeAgent < Apps::Privileged::ClaudeAgent
    include ::AgenticApp
    include Singleton

    sig { override.returns(String) }
    def slug
      Apps::Privileged::ClaudeAgent::SLUG
    end

    sig { override.returns(String) }
    def display_name
      "Claude"
    end

    sig { override.returns(String) }
    def doc_url
      "https://docs.github.com/en/enterprise-cloud@latest/copilot/concepts/agents/anthropic-claude"
    end

    sig { override.returns(T.nilable(Integration)) }
    def integration
      Apps::Privileged.integration(:claude_agent)
    end

    sig { override.returns(T.nilable(Integer)) }
    def bot_id
      integration&.bot_id
    end

    sig { override.returns(T::Boolean) }
    def assignable?
      return false unless integration
      true
    end

    sig { override.returns(T::Boolean) }
    def mentionable?
      return false unless integration
      false
    end

    sig { override.returns(T::Boolean) }
    def global?
      false
    end

    sig { override.params(target: T.any(User, Organization, Business)).returns(T::Boolean) }
    def installed_for_target?(target)
      integration&.installed_on?(target) || false
    end

    sig { override.params(target: T.any(User, Organization, Business)).returns(T::Boolean) }
    def can_be_enabled_for?(target)
      return false unless integration
      target.feature_flag_enabled?(:agentshq_claude, default: false)
    end

    sig do
      override.params(
        repo: T.untyped,
        viewer: T.untyped
      ).returns(T::Boolean)
    end
    def enabled_for_repository?(repo, viewer)
      feature_flag_enabled?(repo) &&
        !restricted_by_policies?(repo, viewer) &&
        installed_on_repository?(integration, repo)
    end

    private

    sig { params(repo: T.untyped).returns(T::Boolean) }
    def feature_flag_enabled?(repo)
      repo.feature_flag_enabled?(:agentshq_claude, default: false) ||
        repo.owner&.feature_flag_enabled?(:agentshq_claude, default: false)
    end

    sig { params(integration: T.nilable(Integration), repo: T.untyped).returns(T::Boolean) }
    def installed_on_repository?(integration, repo)
      return false if integration.nil?

      installation = IntegrationInstallation.with_target(repo.owner).find_by(integration: integration)
      return false unless installation

      installed_repo_ids = installation.repository_ids(resource: "metadata", repository_ids: [repo.id])

      installed_repo_ids.include?(repo.id)
    end

    sig { params(repo: T.untyped, viewer: T.untyped).returns(T::Boolean) }
    def restricted_by_policies?(repo, viewer)
      if !repo.copilot_swe_agent_enabled?(viewer) # For now, we want to restrict Codex Agent to only work if CCA is also enabled
        true
      elsif repo.owner.is_a?(Organization) && !repo.owner.swe_agent_third_party_access_enabled? # check policy
        true
      elsif !AgenticApp.enterprise_opted_in?(self, repo.owner) # check enterprise policy
        true
      else
        false
      end
    end

  end
end
