# typed: strict
# frozen_string_literal: true

module AgenticApp
  # Copilot Code Review Agent - Global agent for code review tasks in pull requests
  class CopilotCodeReviewAgent < Base
    sig { override.returns(String) }
    def slug
      Apps::Privileged::CopilotPullRequestReviewer::SLUG
    end

    sig { override.returns(String) }
    def display_name
      "Copilot Code Review"
    end

    sig { override.returns(String) }
    def display_owner
      "GitHub"
    end

    sig { override.returns(String) }
    def doc_url
      "https://gh.io/copilot-coding-agent-docs"
    end

    sig { override.returns(Symbol) }
    def privileged_app_alias
      :copilot_pull_request_reviewer
    end

    sig { override.returns(Symbol) }
    def disallow_feature_flag
      :copilot_pull_request_reviewer_disallow
    end

    sig { override.returns(Symbol) }
    def policy_feature_flag
      :copilot_code_review_use_sweagentd
    end

    sig { override.returns(T::Boolean) }
    def assignable?
      false
    end

    sig { override.returns(T::Boolean) }
    def mentionable?
      false
    end

    sig { override.returns(T::Boolean) }
    def global?
      true
    end

    sig { override.params(target: T.any(User, Organization, Business)).returns(T::Boolean) }
    def installed_for_target?(target)
      true  # Global agent - always installed
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
      return false unless integration
      return false unless feature_flag_enabled?(repo)

      repo.copilot_swe_agent_enabled?(viewer)
    end
  end
end
