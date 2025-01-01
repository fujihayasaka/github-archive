# typed: strict
# frozen_string_literal: true

module Repository::MergeQueueDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  include GitHub::Memoizer

  requires_ancestor { Repository }

  included do
    T.bind(self, T.class_of(Repository))
    has_many :merge_queues, dependent: :destroy, inverse_of: :repository
  end

  # Public: Is the merge queue feature enabled for this repository?
  sig { returns(T::Boolean) }
  def merge_queue_enabled?
    # Merge queue is globally enabled for this instance
    return false unless GitHub.merge_queues_enabled?

    GitHub.enterprise? || \
      github_owned? || \
      plan_supports?(:merge_queue) || \
      self.feature_flag_enabled_or_raise?(:merge_queue, memoize: false) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
  end

  # Public: Does this repository show extra, not-yet-customer-ready branch protection settings
  #         when using the merge queue?
  sig { returns(T::Boolean) }
  def merge_queue_extra_branch_protection_settings?
    merge_queue_enabled? && feature_flag_enabled_or_raise?(:merge_queue_extra_branch_protection_settings) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
  end

  # Public: Is this repository opted in to use hidden refs (instead of prep branches)?
  sig { returns(T::Boolean) }
  memoize def merge_queue_uses_queue_refs?
    feature_flag_enabled_or_raise?(:merge_queue_uses_queue_refs) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
  end

  # Does the user have permission to add pull requests to the merge queue?
  #
  # user - a User or nil
  # branch_name - optional String branch name to check if the merge queue is enabled
  #
  # Returns: Boolean
  sig { params(user: T.nilable(User), branch_name: T.nilable(String)).returns(T::Boolean) }
  def can_add_pull_requests_to_merge_queue?(user, branch_name: nil)
    return false unless user
    return false unless GitHub.merge_queues_enabled?
    return false unless merge_queue_enabled?
    return false unless writable_by?(user)
    if branch_name.present?
      merge_queue_enabled_for_branch?(branch_name)
    else
      true
    end
  end

  sig { returns(T.nilable(MergeQueue)) }
  memoize def default_merge_queue
    merge_queue_for(branch: default_branch)
  end

  sig { returns(Promise[T.nilable(MergeQueue)]) }
  def async_default_merge_queue
    async_default_branch.then do |branch|
      merge_queue_for(branch: branch)
    end
  end

  sig { params(branch: String).returns(Promise[T.nilable(MergeQueue)]) }
  def async_merge_queue_for(branch:)
    async_merge_queues.then do
      merge_queues.find_by(branch: branch)
    end
  end

  sig { params(branch: String).returns(T.nilable(MergeQueue)) }
  def merge_queue_for(branch:)
    if association(:merge_queues).loaded?
      merge_queues.detect { |queue| queue.branch == branch }
    else
      merge_queues.find_by(branch: branch)
    end
  end

  sig { params(for_branch: String).returns(T::Boolean) }
  def merge_queue_exists?(for_branch:)
    if association(:merge_queues).loaded?
      merge_queues.any? { |queue| queue.branch == for_branch }
    else
      MergeQueue.exists?(repository_id: self.id, branch: for_branch)
    end
  end

  sig { params(branch: T.nilable(String)).returns(T::Boolean) }
  def merge_queue_enabled_for_branch?(branch)
    return false if branch.nil?

    @merge_queue_enabled_for_branch ||= T.let(
      Hash.new do |hash, b|
        next hash[b] = false unless merge_queue_enabled?
        next hash[b] = false unless merge_queue_for(branch: b).present?

        # rubocop:todo GitHub/AvoidCast
        policy_evaluator = BranchRuleEvaluator.for_repository_with_branch_name(T.cast(self, Repository), b)
        # rubocop:enable GitHub/AvoidCast
        next hash[b] = false unless policy_evaluator

        hash[b] = policy_evaluator.merge_queue_enabled?
      end,
      T.nilable(T::Hash[String, T::Boolean])
    )

    @merge_queue_enabled_for_branch[branch]
  end

  # Returns true if the passed commit_id matches the head_oid of any current
  # MergeQueueEntry
  sig { params(commit_id: String).returns(T::Boolean) }
  def merge_queue_commits_include?(commit_id)
    return false unless merge_queue_enabled?
    return false if commit_id == GitHub::NULL_OID

    MergeQueueEntry.where(queue: merge_queues, head_sha: commit_id).exists?
  end
end
