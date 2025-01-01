# typed: true
# frozen_string_literal: true

module PullRequest::MergeQueueDependency
  extend T::Helpers
  extend T::Sig
  extend ActiveSupport::Concern
  include GitHub::Memoizer

  requires_ancestor { PullRequest }

  included do
    T.bind(self, T.class_of(PullRequest))
    has_one :merge_queue_entry, dependent: :destroy, inverse_of: :pull_request
  end

  sig { returns(T::Boolean) }
  def requires_deployments_before_merging?
    return false unless evaluator = base_branch_rule_evaluator
    evaluator.required_deployments_enabled?
  end

  # Public: Check if this pull request's base branch is protected, has a
  # merge queue, and using the merge queue is enforced for the specified user.
  sig { params(actor: User).returns(T::Boolean) }
  def protected_base_branch_merge_queue_enforced_for?(actor)
    return false unless evaluator = base_branch_rule_evaluator
    evaluator.merge_queue_enforced_for?(actor: actor)
  end

  sig { returns(Promise[T::Boolean]) }
  def async_in_merge_queue?
    async_merge_queue.then do |merge_queue|
      next false unless merge_queue
      merge_queue.has_entry_for?(pull_request: self)
    end
  end

  sig { returns(T::Boolean) }
  def in_merge_queue?
    return false unless queue = merge_queue
    queue.has_entry_for?(pull_request: self)
  end

  sig { returns(Promise[T::Boolean]) }
  def async_merge_queue_enabled?
    return Promise.resolve(@merge_queue_enabled) if defined?(@merge_queue_enabled)
    async_base_repository.then { merge_queue_enabled? }
  end

  sig { returns(T::Boolean) }
  def merge_queue_enabled?
    return @merge_queue_enabled if defined?(@merge_queue_enabled)

    repo = repository
    evaluator = base_branch_rule_evaluator
    @merge_queue_enabled = GitHub.merge_queues_enabled? &&
      repo.present? && repo.merge_queue_enabled? &&
      evaluator.present? && evaluator.merge_queue_enabled? &&
      merge_queue.present?
  end

  sig { returns(Promise[T.nilable(MergeQueue)]) }
  def async_merge_queue
    return Promise.resolve(@merge_queue) if defined?(@merge_queue)

    async_base_repository.then do |repo|
      next @merge_queue = nil if repo.nil?
      repo.async_merge_queue_for(branch: base_ref_name).then do |queue|
        @merge_queue = queue
      end
    end
  end

  sig { returns(T.nilable(MergeQueue)) }
  def merge_queue
    return @merge_queue if defined?(@merge_queue)
    @merge_queue = base_repository&.merge_queue_for(branch: base_ref_name)
  end

  sig { params(commit_oid: String).returns(T.nilable(CombinedStatus)) }
  def status_at_commit(commit_oid)
    @status_at_commit ||= {}
    return @status_at_commit[commit_oid] if @status_at_commit.key?(commit_oid)

    commit_statuses = Statuses::Service.current_for_shas(repository_id: repository&.id, shas: commit_oid)
    check_runs = CheckRun.latest_for_sha_and_repository(commit_oid, repository).order(:created_at)

    @status_at_commit[commit_oid] = if commit_statuses.any? || check_runs.any?
      ::CombinedStatus.new(repository, commit_oid, statuses: commit_statuses, check_runs: check_runs)
    end
  end

  sig { returns(Promise[T.nilable(MergeQueueEntry)]) }
  def async_merge_queue_entry
    async_base_repository.then do
      next unless queue = merge_queue
      queue.entry_for(pull_request: self)
    end
  end

  # Public: Check if this pull request's base repository uses a merge queue
  # and one of the pull request's branches is currently locked as part of the
  # merge queue.
  #
  # check_head_ref - Boolean indicating whether the pull request's head
  #                  branch's lock status should be checked; defaults to
  #                  checking the base branch's lock status
  sig { params(check_head_ref: T::Boolean).returns(T::Boolean) }
  def branch_locked_for_merge_queue?(check_head_ref: false)
    branch_name = check_head_ref ? head_ref : base_ref
    MergeQueue.branch_locked_for_merge_queue?(branch_name, repository: base_repository)
  end
end
