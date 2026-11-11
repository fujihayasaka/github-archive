# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class MergeQueuePostMergeJob < ApplicationJob
  queue_as :merge_queue
  retry_on_dirty_exit

  discard_on ActiveJob::DeserializationError, GitRPC::ObjectMissing
  retry_on_recoverable_exceptions

  sig do
    params(
      repository: Repository,
      branch: String,
      pull_request: PullRequest,
      actor: User,
      merge_commit_oid: String,
      merge_time: ActiveSupport::TimeWithZone,
      merge_method: Symbol,
      merge_action: Symbol,
      merge_base_sha: T.nilable(String),
      merge_group_pull_request_ids: T::Array[Integer],
    ).void
  end
  def perform(repository:, branch:, pull_request:, actor:, merge_commit_oid:, merge_time:, merge_method:, merge_action:, merge_base_sha: nil, merge_group_pull_request_ids: [])
    PullRequests::Observability::Git.tag(repository:, feature: :merge_queue_post_merge_job) do
      # Retarget the next unmerged PR in the stack to the stack's base branch.
      # Runs before post_merge so intermediate branches are still available.
      # Must run even if the PR is already marked merged (e.g. by PR sync),
      # because the stack retarget is a side effect of the merge queue merge.
      with_write do
        retarget_remaining_stack_base(pull_request, actor:, repository:, merge_group_pull_request_ids:)
      end

      # If PR sync has completed already the PR will be marked as merged. Skip running this.
      return if pull_request.merged?

      if repository.feature_flag_enabled?(:load_installation_for_merge_queue_post_merge_job, default: false)
        if actor.is_a?(Bot) && !actor.installation
          actor.async_load_installation_for(repository).sync
        end
      end

      merge_commit = repository.commits.find(merge_commit_oid)

      with_write do
        pull_request.post_merge(
          actor,
          merge_commit,
          branch,
          merge_commit_oid,
          merge_time,
          merge_method,
          merge_action,
          enqueue_push_job: false,
          merge_base_sha:,
        )

        GitHub.instrument("pull_request.dequeued",
          pull_request_id: pull_request.id,
          actor_id: actor.id,
          reason: MergeQueues::Entry::RemovalReason::Merged.to_hydro_enum_value,
        )

        if repository.delete_branch_on_merge?
          pull_request.cleanup_head_ref(actor)
        end
      end

      if stack = pull_request.stack
        if FeatureFlag.vexi.enabled?(:pull_request_stack_merge_hydro_events, repository, default: false)
          GlobalInstrumenter.instrument("pull_request_stack.merge", {
            merge_action: merge_action.to_s.upcase.to_sym,
            merge_method: merge_method.to_s.upcase.to_sym,
            stack_id: stack.id,
            stack_number: stack.number,
            stack_base_branch: stack.base_ref,
            repository: repository,
            pull_requests_merged: [pull_request],
            stack_size: stack.entry_count,
            actor: actor,
          })
        end
      end
    end
  end

  private

  sig { params(pull_request: PullRequest, actor: User, repository: Repository, merge_group_pull_request_ids: T::Array[Integer]).void }
  def retarget_remaining_stack_base(pull_request, actor:, repository:, merge_group_pull_request_ids: [])
    return unless repository.feature_flag_enabled?(:pull_request_stacks, default: false)
    return unless pull_request.stacked?
    return unless stack = pull_request.stack
    return unless position = pull_request.stack_position

    next_entry = stack.entries.find_by(position: position + 1)
    return unless next_entry
    return unless next_base_pull = next_entry.pull_request

    # Skip if the next PR was merged in the same merge group — its own
    # post-merge job will handle retargeting when it runs.
    return if merge_group_pull_request_ids.include?(next_base_pull.id)

    return if next_base_pull.merged?
    return if next_base_pull.in_merge_queue?
    return if next_base_pull.base_ref == stack.base_ref

    prior_base = next_base_pull.display_base_ref_name
    target_base = stack.base_ref

    GitHub.logger.info(
      "Retargeting remaining stack base",
      "gh.pull_request.id": next_base_pull.id,
      "gh.stacks.retarget_to": target_base,
      "gh.stacks.prior_base": prior_base,
    )

    next_base_pull.change_base_branch(actor, target_base, automatic: true)

    if actor.is_a?(User)
      pulls = stack.pulls_from(next_base_pull)
      if pulls.any?
        PullRequests::Stacks::UpdateAllBranchesJob.perform_later(
          actor:,
          start_pull_request: next_base_pull,
          expected_head_oid_by_pr_number: pulls.to_h { [_1.number.to_s, _1.head_sha] },
        )
      end
    end
  rescue PullRequest::BaseNotChangeableError => err
    begin
      next_base_pull&.create_issue_event(:automatic_base_change_failed,
        actor,
        message: err.error_type_key,
        title_was: prior_base,
        title_is: target_base)
    rescue ActiveRecord::ActiveRecordError => event_err
      Failbot.report(event_err, "gh.pull_request.id": next_base_pull&.id)
    end
  rescue => err
    Failbot.report(err, "gh.pull_request.id": next_base_pull&.id)
  end
end
