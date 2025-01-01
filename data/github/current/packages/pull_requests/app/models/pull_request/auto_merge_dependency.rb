# typed: true
# frozen_string_literal: true

module PullRequest::AutoMergeDependency
  extend T::Helpers

  requires_ancestor { PullRequest }

  sig { void }
  def perform_auto_merge
    return if merged?
    return unless auto_merge_request = self.auto_merge_request

    GitHub.dogstats.increment("pull_request.auto_merge_attempted")

    merge_state = merge_state(viewer: auto_merge_request.user)

    if merge_state.blocked_by_unauthorized_protection?
      auto_merge_request.disable(:denied)
      return
    end

    unless merge_state.clean? || merge_state.unstable? || merge_state.has_hooks?
      auto_merge_request.update(merge_error: :not_mergeable)
      GitHub.dogstats.increment("pull_request.auto_merge.bail_for_bad_merge_state", tags: ["merge_state:#{merge_state.status}"])
      return
    end

    if merge_state.blocked_only_by_required_linear_history? && auto_merge_request.auto_merge?
      auto_merge_request.update(merge_error: :merge_commit)
      GitHub.dogstats.increment("pull_request.auto_merge.bail_for_bad_merge_state", tags: ["merge_state:#{merge_state.status}"])
      return
    end

    reflog_data = {}
    reflog_data[:real_ip] = auto_merge_request.actor_ip_address if auto_merge_request.actor_ip_address

    success, _, code = merge(
      auto_merge_request.user,
      author_email: auto_merge_author_email,
      message_title: auto_merge_request.commit_title,
      message: auto_merge_request.commit_message,
      method: auto_merge_request.minimal_merge_method,
      merge_action: :auto_merge,
      merge_state_status: merge_state.status,
      reflog_data:
    )

    if success
      GitHub.dogstats.increment("pull_request.auto_merge_succeeded")
    elsif code == :parent_mismatch
      GitHub.dogstats.increment("pull_request.auto_merge.retried_on_parent_mismatch")
      raise Git::Ref::ComparisonMismatch
    else
      GitHub.dogstats.increment("pull_request.auto_merge_failed", tags: ["code:#{code}"])
      auto_merge_request.disable(code)
    end
  end

  # The email address to use for the merge
  #
  # auto_merge_author_email should be nil if
  # user.author_emails returns an empty array,
  # otherwise the merge will fail with an ArgumentError
  sig { returns(T.nilable(String)) }
  def auto_merge_author_email
    if auto_merge_request&.user&.author_emails.empty?
      nil
    else
      auto_merge_request&.commit_email_address&.email
    end
  end

  sig { void }
  def enqueue_auto_merge_job_if_enabled
    return unless auto_merge_request

    AutoMergeJob.perform_later(self)
  end

  class CanEnableAutoMergeNotAllowedResult
    attr_reader :reason

    def initialize(reason: nil)
      @reason = reason
    end

    def allowed?
      reason.blank?
    end
  end

  class CanEnableAutoMergeAllowedResult
    def allowed?
      true
    end

    def reason
      nil
    end
  end

  sig { params(actor: T.untyped).returns(T.any(CanEnableAutoMergeNotAllowedResult, CanEnableAutoMergeAllowedResult)) }
  def can_enable_auto_merge(actor:)

    repository = T.must(self.repository)

    if repository.advisory_workspace? && !FeatureFlag.vexi.enabled?(:auto_merge_advisory_workspace_prs, default: false)
      return CanEnableAutoMergeNotAllowedResult.new(reason: "Temporary private forks do not support auto merge")
    end

    if auto_merge_enabled?
      return CanEnableAutoMergeNotAllowedResult.new(reason: "Auto merge is already enabled")
    end

    if draft?
      return CanEnableAutoMergeNotAllowedResult.new(reason: "Pull request is a draft")
    end

    if closed?
      return CanEnableAutoMergeNotAllowedResult.new(reason: "Pull request is closed")
    end

    if merged?
      return CanEnableAutoMergeNotAllowedResult.new(reason: "Pull request is already merged")
    end

    unless repository.async_pushable_by?(actor).sync && base_repository&.async_pushable_by?(actor)&.sync
      return CanEnableAutoMergeNotAllowedResult.new(reason: "User is not allowed to push to this repository")
    end

    pr_merge_state = cached_merge_state(viewer: actor)

    if pr_merge_state.blocked_by_workflow_updates?
      return CanEnableAutoMergeNotAllowedResult.new(reason: pr_merge_state.blocked_by_workflow_updates_message)
    end

    pr_status = pr_merge_state.status

    unless [:dirty, :blocked, :unknown, :behind].include?(pr_status)
      return CanEnableAutoMergeNotAllowedResult.new(reason: "Pull request is in #{pr_status} status")
    end

    unless base_branch_rule_evaluator.present?
      return CanEnableAutoMergeNotAllowedResult.new(reason: "Protected branch rules not configured for this branch")
    end

    base_branch_rule_evaluator = T.must(self.base_branch_rule_evaluator)

    unless base_branch_rule_evaluator.authorized?(actor)
      return CanEnableAutoMergeNotAllowedResult.new(reason: "User is not authorized for this protected branch")
    end

    if pr_merge_state.blocked_by_invalid_merge_queue_config?
      return CanEnableAutoMergeNotAllowedResult.new(reason: pr_merge_state.blocked_by_invalid_merge_queue_config_message)
    end

    # if MergeQueue is enabled and there is no entry for this PR
    # we don't need to perform status checks beyond the ones above
    # as the MergeQueue will handle the checks
    # note that this line checks if MergeQueue applies to this PR AND no entry for it exists
    if merge_queue = self.merge_queue
      if merge_queue.entry_for(pull_request: self).blank?
        return CanEnableAutoMergeAllowedResult.new
      end
    end

    # these checks are for AutoMerge without MergeQueue
    unless repository.auto_merge_allowed?
      return CanEnableAutoMergeNotAllowedResult.new(reason: "Auto merge is not allowed for this repository")
    end

    unless repository.can_auto_merge_be_allowed?
      return CanEnableAutoMergeNotAllowedResult.new(reason: "Auto merge cannot be allowed for this repository")
    end

    if [
      base_branch_rule_evaluator.pull_request_reviews_enabled?,
      base_branch_rule_evaluator.required_status_checks_enabled?,
      base_branch_rule_evaluator.required_review_thread_resolution_enabled?,
      base_branch_rule_evaluator.code_scanning_enabled?
    ].none?
      return CanEnableAutoMergeNotAllowedResult.new(reason: "Branch does not have required protected branch rules")
    end

    CanEnableAutoMergeAllowedResult.new
  end

  sig { params(actor: T.untyped).returns(T::Boolean) }
  def disable_auto_merge_allowed?(actor:)
    !draft? &&
    !closed? &&
    !merged? &&
    (T.must(repository).pushable_by?(actor) || actor == user)
  end

  sig { params(actor: T.untyped).returns(T::Boolean) }
  def can_disable_auto_merge?(actor:)
    disable_auto_merge_allowed?(actor:) && auto_merge_request.present?
  end

  # Auto-merge should be disabled when the head is pushed to by a
  # user without write access or if the base branch is changed
  sig { params(before: String, after: String, user: T.untyped, changing_base: T.nilable(T::Boolean)).void }
  def disable_auto_merge_if_non_writer_pushed_or_changed_base(before:, after:, user:, changing_base:)
    return unless auto_merge_request = self.auto_merge_request
    return unless repository = self.repository

    # Merge Queue will always be allowed to push.
    return if user == MergeQueues.system_actor

    # If the user has access we do not need to disable the auto merge.
    return if repository.async_pushable_by?(user).sync

    if changing_base
      auto_merge_request.disable(:base_changed_by_non_writer)
    elsif reviewable_changes?(before:, after:)
      auto_merge_request.disable(:push_from_non_writer)
    end
  end

  private

  sig { returns(T::Boolean) }
  def auto_merge_enabled?
    # AutoMerge has already been enabled if either an AutoMergeRequest or a MergeQueueEntry exist for this PR
    # MergeQueue may create an AutoMergeRequest while waiting on required checks

    # .persisted? is necessary because the AutoMergeRequest calls can_enable_auto_merge on: :create
    # which would always be true for when checking existence
    auto_merge_request&.persisted? || in_merge_queue?
  end
end
