# typed: true
# frozen_string_literal: true

# Executes the MergeQueueJob after a delay.
#
# We use a separate job for this so that the lock for the regular MergeQueueJob
# isn't held by a queued instance when we want to run later, e.g. after five
# minutes.
#
# Don't call this job directly: use `MergeQueues.delayed_execute!` instead.
class MergeQueueDelayedJob < ApplicationJob
  extend T::Sig

  include ActiveJob::InitiallyEnqueuedAt

  queue_as :merge_queue

  discard_on ActiveJob::DeserializationError
  discard_on GitHub::Restraint::UnableToLock

  retry_on_recoverable_exceptions

  locked_by timeout: 10.minutes, key: ->(job) {
    repository, branch = job.arguments
    "merge-queue-delayed-#{repository&.id}-#{branch}"
  }

  sig { params(repository: Repository, branch: String).void }
  def perform(repository, branch)
    MergeQueues.execute!(repository, branch)
  end
end
