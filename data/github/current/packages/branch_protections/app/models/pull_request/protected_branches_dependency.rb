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

  sig { params(actor: T.untyped).returns(Symbol) }
  def default_merge_method_for(actor)
    base_branch_rule_evaluator&.default_merge_method_for(actor) || base_repository&.default_merge_method_for(actor) || :merge
  end

  sig { returns(Promise[T::Boolean]) }
  def async_merge_commit_allowed?
    async_base_repository.then do |base_repository|
      if base_repository.feature_enabled_for_source?(:pull_request_rule_merge_types)
        async_batch_base_branch_rule_evaluator.then do |evaluator|
          if (types = evaluator&.supported_merge_types) && !types.include?("merge")
            false
          else
            base_repository ? base_repository&.async_merge_commit_allowed? : true
          end
        end
      else
        base_repository ? base_repository&.async_merge_commit_allowed? : true
      end
    end
  end

  sig { returns(T::Boolean) }
  def merge_commit_allowed?
    async_merge_commit_allowed?.sync
  end

  sig { returns(Promise[T::Boolean]) }
  def async_squash_merge_allowed?
    async_base_repository.then do |base_repository|
      if base_repository.feature_enabled_for_source?(:pull_request_rule_merge_types)
        async_batch_base_branch_rule_evaluator.then do |evaluator|
          if (types = evaluator&.supported_merge_types) && !types.include?("squash")
            false
          else
            base_repository ? base_repository&.async_squash_merge_allowed? : true
          end
        end
      else
        base_repository ? base_repository&.async_squash_merge_allowed? : true
      end
    end
  end

  sig { returns(T::Boolean) }
  def squash_merge_allowed?
    async_squash_merge_allowed?.sync
  end

  sig { returns(Promise[T::Boolean]) }
  def async_rebase_merge_allowed?
    async_base_repository.then do |base_repository|
      if base_repository.feature_enabled_for_source?(:pull_request_rule_merge_types)
        async_batch_base_branch_rule_evaluator.then do |evaluator|
          if (types = evaluator&.supported_merge_types) && !types.include?("rebase")
            false
          else
            base_repository ? base_repository&.async_rebase_merge_allowed? : true
          end
        end
      else
        base_repository ? base_repository&.async_rebase_merge_allowed? : true
      end
    end
  end

  sig { returns(T::Boolean) }
  def rebase_merge_allowed?
    async_rebase_merge_allowed?.sync
  end
end
