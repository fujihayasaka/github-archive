# typed: true
# frozen_string_literal: true

# Once a Merge Queue has been disabled, this cleans up after it.
class MergeQueueDisableJob < ApplicationJob

  include ActiveJob::InitiallyEnqueuedAt

  queue_as :merge_queue

  discard_on ActiveJob::DeserializationError

  retry_on_recoverable_exceptions

  locked_by timeout: 5.minutes, key: ->(job) {
    repository = job.arguments.first
    "merge-queue-disable-#{repository.id}"
  }

  sig { params(repository: Repository).void }
  def perform(repository)
    MergeQueues::Service::Disable.new(repository).call
  end
end
