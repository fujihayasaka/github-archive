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
      base_repos = pulls.filter_map(&:base_repository)
      GitHub::PrefillAssociations.prefill_associations(base_repos.filter_map { _1.owner if _1.owner.is_a?(Organization) }, :business)
      if FeatureFlag.vexi.enabled_or_raise?(:use_billing_locked_rather_than_disabled) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        # The repository customer is needed to determine if the owner is disabled
        GitHub::PrefillAssociations.prefill_batch_method(base_repos, :plan_customer_disabled?)
      end

      GitHub::PrefillAssociations.prefill_associations(pulls, [:repository], available_records: base_repos)
      stacks_enabled = FeatureFlag.vexi.enabled?(
        :pull_request_stacks,
        pulls.filter_map(&:repository),
        default: false,
      )
      if stacks_enabled
        GitHub::PrefillAssociations.prefill_associations(pulls, [:stack_entry, :stack])
      end

      pulls.group_by(&:base_repository_id).each do |repo_id, repo_pulls|
        next if repo_id.nil?

        repo = repo_pulls.first.base_repository
        next if repo.nil?

        ref_names = repo_pulls.map(&:stack_or_pull_base_ref_name).uniq

        BranchRuleEvaluator.for_repository_with_branch_names(repo, ref_names).each do |ref_name, protected_branch|
          branches_by_repo_and_ref_name[[repo_id, ref_name]] = protected_branch
        end
      end

      pulls.index_with do |pull|
        branches_by_repo_and_ref_name[[pull.base_repository_id, pull.stack_or_pull_base_ref_name]]
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

  # Returns a hash of merge method statuses for the given actor.
  # Format: { merge_method => :allowed | :blocked | :allowed_with_bypass }
  # merge_methods are :merge, :squash, and :rebase
  # This method considers both branch protection rules and repo merge method settings.
  sig { params(actor: T.nilable(User)).returns(Promise[T::Hash[Symbol, Symbol]]) }
  def async_merge_method_statuses(actor: nil)
    async_base_repository.then do |base_repository|
      next BranchRuleEvaluator::ALL_MERGE_METHODS_ALLOWED.dup unless base_repository
      async_batch_base_branch_rule_evaluator.then do |evaluator|
        merge_method_statuses = evaluator&.supported_merge_methods(actor:) || BranchRuleEvaluator::ALL_MERGE_METHODS_ALLOWED.dup
        Promise.all([
          base_repository.async_merge_commit_allowed?,
          base_repository.async_squash_merge_allowed?,
          base_repository.async_rebase_merge_allowed?,
        ]).then do |(merge_commit_allowed, squash_merge_allowed, rebase_merge_allowed)|
          merge_method_statuses[:merge] = :blocked unless merge_commit_allowed
          merge_method_statuses[:squash] = :blocked unless squash_merge_allowed
          merge_method_statuses[:rebase] = :blocked unless rebase_merge_allowed

          merge_method_statuses
        end
      end
    end
  end

  sig { params(actor: T.untyped).returns(Promise[T::Boolean]) }
  def async_merge_commit_allowed?(actor: nil)
    async_merge_method_statuses(actor: actor).then { |merge_method_statuses| merge_method_statuses[:merge] != :blocked }
  end

  sig { params(actor: T.untyped).returns(T::Boolean) }
  def merge_commit_allowed?(actor: nil)
    async_merge_commit_allowed?(actor:).sync
  end

  sig { params(actor: T.untyped).returns(Promise[T::Boolean]) }
  def async_squash_merge_allowed?(actor: nil)
    async_merge_method_statuses(actor:).then { |merge_method_statuses| merge_method_statuses[:squash] != :blocked }
  end

  sig { params(actor: T.untyped).returns(T::Boolean) }
  def squash_merge_allowed?(actor: nil)
    async_squash_merge_allowed?(actor:).sync
  end

  sig { params(actor: T.untyped).returns(Promise[T::Boolean]) }
  def async_rebase_merge_allowed?(actor: nil)
    async_merge_method_statuses(actor:).then { |merge_method_statuses| merge_method_statuses[:rebase] != :blocked }
  end

  sig { params(actor: T.untyped).returns(T::Boolean) }
  def rebase_merge_allowed?(actor: nil)
    async_rebase_merge_allowed?(actor:).sync
  end

  sig { params(actor: T.untyped).returns(T::Boolean) }
  def include_rebase_commit?(actor: nil)
    if GitHub.skip_rebase_commit_generation_from_rebase_merge_settings
      rebase_merge_allowed = rebase_merge_allowed?(actor:)

      tags = ["path:skip_from_rebase_merge_settings", "rebase_merge_allowed:#{rebase_merge_allowed}"]
      GitHub.dogstats.increment("pull_request.include_rebase_commit", tags: tags)
      rebase_merge_allowed
    elsif FeatureFlag.vexi.enabled?(:reduce_rebase_commit_generation_cprmc, base_repository, default: false)
      skip_rebase_via_api = FeatureFlag.vexi.enabled?(:merge_commit_request_skip_rebase_via_api, base_repository, default: false)
      tags = ["path:reduce_rebase_commit_generation_cprmc"]

      if skip_rebase_via_api
        tags << "rebase_merge_allowed:false"
        tags << "skip_rebase_via_api:true"
        GitHub.dogstats.increment("pull_request.include_rebase_commit", tags: tags)
        return false
      end

      rebase_merge_allowed = rebase_merge_allowed?(actor:)
      tags << "rebase_merge_allowed:#{rebase_merge_allowed}"

      GitHub.dogstats.increment("pull_request.include_rebase_commit", tags: tags)
      rebase_merge_allowed
    else
      skip_feature_enabled = FeatureFlag.vexi.enabled?(:merge_commit_request_skip_rebase_via_api, base_repository, default: false)
      pull_merge_commit_allowed = merge_commit_allowed?(actor:)
      pull_rebase_merge_allowed = rebase_merge_allowed?(actor:)

      include_rebase_commit = !skip_feature_enabled || pull_merge_commit_allowed || pull_rebase_merge_allowed

      tags = ["path:default",
              "skip_feature_enabled:#{!skip_feature_enabled}",
              "pull_merge_commit_allowed:#{pull_merge_commit_allowed}",
              "pull_rebase_merge_allowed:#{pull_rebase_merge_allowed}",
              "rebase_merge_allowed:#{include_rebase_commit}"]
      GitHub.dogstats.increment("pull_request.include_rebase_commit", tags: tags)

      include_rebase_commit
    end
  end
end
