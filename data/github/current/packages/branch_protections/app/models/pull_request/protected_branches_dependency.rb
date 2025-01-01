# typed: true
# frozen_string_literal: true

module PullRequest::ProtectedBranchesDependency
  include GitHub::BatchMethod
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { PullRequest }

  included do
    batch_method(:base_branch_rule_evaluator, T.nilable(BranchRuleEvaluator)) do |pulls|
      branches_by_repo_and_ref_name = {}

      # BranchRuleEvaluator uses the organization to load org-wide rules. Preload now for performance.
      GitHub::PrefillAssociations.prefill_associations(pulls, { base_repository: [:organization, :owner] })
      GitHub::PrefillAssociations.prefill_associations(pulls.map(&:base_repository).filter_map { _1&.owner if _1&.owner.is_a?(Organization) }, :business)

      pulls.group_by(&:base_repository_id).each do |repo_id, repo_pulls|
        next if repo_id.nil?

        repo = repo_pulls.first.base_repository
        next if repo.nil?

        ref_names = repo_pulls.map(&:base_ref_name).uniq

        BranchRuleEvaluator.for_repository_with_branch_names(repo, ref_names).each do |ref_name, protected_branch|
          branches_by_repo_and_ref_name[[repo_id, ref_name]] = protected_branch
        end
      end

      pulls.index_with do |pull|
        branches_by_repo_and_ref_name[[pull.base_repository_id, pull.base_ref_name]]
      end
    end
  end

  def head_branch_rule_evaluator
    return @head_branch_rule_evaluator if defined?(@head_branch_rule_evaluator)
    @head_branch_rule_evaluator = BranchRuleEvaluator.for_repository_with_branch_name(T.must(head_repository), head_ref_name)
  end

  def revert_branch_rule_evaluator
    return @revert_branch_rule_evaluator if defined?(@revert_branch_rule_evaluator)
    @revert_branch_rule_evaluator = BranchRuleEvaluator.for_repository_with_branch_name(T.must(base_repository), revert_branch_name)
  end

  # Has the user pushed to the head ref since this PR was opened when
  # that is not allowed by the protected branch?
  def user_has_violated_push_rule?(user)
    base_branch_rule_evaluator&.ignore_approvals_from_contributors? && pushed_to_head_since_open?(user)
  end
end
