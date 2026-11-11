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

    sig { override.returns(AgenticApp::Group) }
    def group
      AgenticApp::Group::REVIEW
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
      return false unless integration
      return false unless feature_flag_enabled?(repo)

      if repo.feature_flag_enabled?(:ccr_use_new_policy_on_cca, default: false)
        # Delegate to CodeReviewAccess for CCR-specific policy checks
        # (enterprise global block, actor eligibility via Copilot policy, quota)
        access = ::PullRequests::Copilot::CodeReviewAccess.new(
          actor: viewer.is_a?(User) ? viewer : nil,
          current_repository: repo
        )
        access.can_create_review_request?
      else
        repo.copilot_swe_agent_enabled?(viewer)
      end
    end

    private

    sig { params(repo: T.untyped).returns(T::Boolean) }
    def feature_flag_enabled?(repo)
      # CCR evaluates its own app-specific disallow flag; copilot_swe_agent_disallow
      # only gates Copilot SWE Agent and third-party coding agents.
      return false if repo.feature_flag_enabled?(disallow_feature_flag, default: false)

      owner = repo.owner
      return false if owner&.feature_flag_enabled?(disallow_feature_flag, default: false)

      business = AgenticApp.business_for(repo.owner)
      return false if business&.feature_flag_enabled?(disallow_feature_flag, default: false)

      if business
        return true if business.feature_flag_enabled?(policy_feature_flag, default: false)
      end

      repo.feature_flag_enabled?(policy_feature_flag, default: false) ||
        owner&.feature_flag_enabled?(policy_feature_flag, default: false)
    end
  end
end
