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
      merge_base_sha: T.nilable(String)
    ).void
  end
  def perform(repository:, branch:, pull_request:, actor:, merge_commit_oid:, merge_time:, merge_method:, merge_action:, merge_base_sha: nil)
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
  end
end
