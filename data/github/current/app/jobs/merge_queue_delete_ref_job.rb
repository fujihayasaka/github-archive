# typed: true
# frozen_string_literal: true

# Removes stale refs no longer needed by the Merge Queue.
class MergeQueueDeleteRefJob < ApplicationJob
  extend T::Sig

  include ActiveJob::InitiallyEnqueuedAt

  queue_as :merge_queue

  discard_on ActiveJob::DeserializationError

  retry_on_recoverable_exceptions

  sig { params(repository: Repository, branch: String, refnames: T::Array[String]).void }
  def perform(repository, branch, refnames)
    # MergeQueue#delete_refs does other behavior if the collection is empty.
    return if refnames.blank?

    # Don't do anything if we can't find the queue.
    return unless merge_queue = MergeQueue.find_by(repository:, branch:)

    with_write do
      merge_queue.delete_refs(
        refnames:,
        actor: MergeQueues.system_actor,
        reraise: true
      )
    rescue Git::Ref::ComparisonMismatch, Git::Ref::UpdateFailed => exception
      # In this scenario the refs may be undeletable, but shouldn't block the queue.
      Failbot.report(exception)
    end
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def logging_context
    repo, branch, _ = arguments

    super.merge({
      repository: repo.name_with_display_owner,
      branch:,
    })
  end
end
