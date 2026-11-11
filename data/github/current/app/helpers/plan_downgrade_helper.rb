# typed: strict
# frozen_string_literal: true

module PlanDowngradeHelper

  include FeatureFlagHelper

  MAX_PRIVATE_REPOS_FOR_DOWNGRADE_COUNTS = 10

  sig do
    params(plan: GitHub::Plan, downgrade: GitHub::Plan, path: String, exit: String, as_safe_data_attributes: T::Boolean)
      .returns(T.any(T::Hash[String, String], String))
  end
  def downgrade_exit_attributes(plan:, downgrade:, path:, exit:, as_safe_data_attributes: false)
    (as_safe_data_attributes ? "" : {})
  end

  sig do
    params(plan: GitHub::Plan, downgrade: GitHub::Plan, path: String, as_safe_data_attributes: T::Boolean)
      .returns(T.any(T::Hash[String, String], String))
  end
  def downgrade_action_attributes(plan:, downgrade:, path:, as_safe_data_attributes: false)
    (as_safe_data_attributes ? "" : {})
  end

  sig { returns(T::Boolean) }
  def downgrade_target_has_plan?
    # https://github.com/github/app-partitioning/issues/53
    current_user = T.unsafe(self).current_user
    current_organization = T.unsafe(self).current_organization

    if current_organization.present?
      can_manage_plan = current_organization.billing_manager?(current_user) || current_organization.adminable_by?(current_user)
      return false unless can_manage_plan
      return true unless current_organization.plan.free?
    else
      return true unless current_user.plan.free?
    end
    false
  end

  sig { params(feature: Symbol, repo_ids: T::Array[Integer]).returns(Integer) }
  def count_for_downgrade_feature(feature, repo_ids)
    return 0 if repo_ids.blank?

    case feature
    when :protected_branches
      ProtectedBranch.where(repository_id: repo_ids).count
    when :draft_prs
      PullRequest.where(repository_id: repo_ids, work_in_progress: true).count
    when :pages
      Page.where(repository_id: repo_ids).count
    when :wikis
      RepositoryWiki.where(repository_id: repo_ids).count
    else
      0
    end
  end

  sig { params(count: Integer).returns(String) }
  def format_downgrade_feature_usage_count(count)
    if count > MAX_PRIVATE_REPOS_FOR_DOWNGRADE_COUNTS
      "#{MAX_PRIVATE_REPOS_FOR_DOWNGRADE_COUNTS}+"
    else
      count.to_s
    end
  end

  sig { params(target: T.any(User, Organization)).returns(T::Hash[Symbol, String]) }
  def downgrade_features_with_counts(target)
    {
      protected_branches: "Protected branches in private repos",
      draft_prs: ("Draft PRs in private repos" if target.plan_supports?(:draft_prs, visibility: :private)),
      pages: "GitHub Pages in private repos",
      wikis: "Wikis in private repos",
    }.compact
  end
end
