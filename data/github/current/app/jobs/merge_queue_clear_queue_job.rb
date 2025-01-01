# typed: true
# frozen_string_literal: true

class MergeQueueClearQueueJob < ApplicationJob
  include ActiveJob::InitiallyEnqueuedAt

  queue_as :merge_queue

  discard_on ActiveJob::DeserializationError

  retry_on_recoverable_exceptions

  retry_on GitHub::Restraint::UnableToLock, wait: 10.seconds, attempts: 100

  locked_by timeout: 1.minute, key: ->(job) {
    args = job.arguments.first
    "clear-queue-#{args[:queue]&.id}"
  }

  def perform(queue:, actor:)
    return if queue.blank?

    with_write do
      MergeQueues.clear!(repository: queue.repository, branch: queue.branch, actor:)
    end
  end
end
