# typed: strict
# frozen_string_literal: true

# This handles work that can be done asyncronously when an item is removed
# from the merge queue, this reduces the chance of timeout on `mergeLockedMergeGroup`
# when called syncronously from Heaven or other third parties
class MergeQueueEntryRemovedJob < ApplicationJob
  extend T::Sig

  queue_as :merge_queue

  discard_on ActiveJob::DeserializationError, GitRPC::ObjectMissing, ActiveRecord::RecordNotFound

  retry_on_recoverable_exceptions

  REMOVED_EVENT = "removed_from_merge_queue"

  # NOTE: batch-enqueued jobs don't run enqueue callbacks, which means that
  # things like `LockingJob` won't work here.
  sig { params(instances: T::Array[MergeQueueEntryRemovedJob]).void }
  def self.perform_all_later(instances)
    ActiveJob.perform_all_later(instances)
  end

  sig do
    params(
      queue_id: T.nilable(Integer),
      created_at: T.any(Time, ActiveSupport::TimeWithZone),
      pull_request_id: Integer,
      actor_id: T.nilable(Integer),
      message: T.nilable(T.any(Symbol, String)),
      before_commit_oid: T.nilable(String),
      subject: User
    ).void
  end
  def perform(queue_id:, created_at:, pull_request_id:, actor_id:, message:, before_commit_oid:, subject:)
    with_write do
      pull_request = PullRequest.find(pull_request_id)
      # Create the removal event on the PR timeline
      # without this job the `destroy!` call on `MergeQueueEntry`
      # triggers this via the `create_removed_from_merge_queue_issue_event` on
      # MergeQueueEntry
      pull_request.events.create(
        created_at: ,
        event: REMOVED_EVENT,
        actor_id:,
        message:,
        before_commit_oid:,
        subject:
      )

      if queue_id
        queue = MergeQueue.find_by(id: queue_id)
        queue&.notify_subscribers(pull_request:)
      end
    end
  end
end
