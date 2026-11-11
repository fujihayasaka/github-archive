# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class MergeQueueShaUpdateJob < ApplicationJob

  include ActiveJob::InitiallyEnqueuedAt

  queue_as :merge_queue
  retry_on_dirty_exit

  discard_on ActiveJob::DeserializationError

  retry_on_recoverable_exceptions

  resolve_tenant_context do |repository|
    Business.find_by(id: repository.tenant_id)
  end

  sig { params(repository: T.nilable(Repository), branch: String, head_sha: String).void }
  def perform(repository, branch, head_sha)
    return unless repository
    return unless queue = MergeQueue.find_by(repository:, branch:)
    return unless entry = queue.entries.find_by(head_sha:)
    return unless pull_request = entry.pull_request

    # Notify for websocket changes.
    queue.notify_socket_subscribers
    queue.notify_subscribers(pull_request:)

    # Build the queue.
    MergeQueues.execute!(repository, queue.branch)
  end
end
