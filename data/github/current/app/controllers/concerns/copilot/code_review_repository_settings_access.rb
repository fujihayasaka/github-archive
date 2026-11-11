# typed: strict
# frozen_string_literal: true

module Copilot::CodeReviewRepositorySettingsAccess
  extend T::Helpers
  extend ActiveSupport::Concern
  include GitHub::Memoizer

  requires_ancestor { AbstractRepositoryController }

  private

  sig { returns(T::Boolean) }
  def qualified_approval_setting_enabled_for_current_rollout?
    current_repository.feature_enabled_for_repo_or_owner?(:ccr_copilot_qualified_approvals)
  end

  sig { returns(T::Boolean) }
  def qualified_approval_setting_allowed_for_current_repository?
    approval_generation_effectively_enabled? && approval_policy.qualified_approval_enabled?
  end

  sig { returns(T::Boolean) }
  def auto_approve_reviews_feature_enabled?
    current_repository.feature_enabled_for_repo_or_owner?(:ccr_auto_approve_reviews)
  end

  sig { returns(T::Boolean) }
  def force_qualified_approval_feature_enabled?
    FeatureFlag.vexi.enabled?(
      :ccr_force_copilot_qualified_approvals,
      current_repository,
      current_repository.owner,
      default: false,
    )
  end

  sig { params(setting_name: String).returns(T::Boolean) }
  def setting_forced_for_current_repository?(setting_name)
    case setting_name
    when "repo_qualified_approval_when_delegated"
      force_qualified_approval_feature_enabled?
    else
      false
    end
  end

  sig { returns(T::Boolean) }
  def approval_generation_effectively_enabled?
    approval_policy.approval_enabled?
  end

  sig { returns(T::Boolean) }
  def mcp_feature_enabled?
    current_repository.feature_enabled_for_repo_or_owner?("copilot-code-reviews-enable-mcp-proxy")
  end

  sig { returns(PullRequests::Copilot::QualifiedApprovalPolicy) }
  memoize def approval_policy
    PullRequests::Copilot::QualifiedApprovalPolicy.new(repository: current_repository)
  end
end
