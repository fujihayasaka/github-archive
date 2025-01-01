# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Cancels the check suites for a merge group, used when an item is removed from the merge queue.
class MergeQueueCancelCheckSuiteJob < ApplicationJob

  include ActiveJob::InitiallyEnqueuedAt
  include GitHub::Memoizer

  queue_as :merge_queue
  retry_on_dirty_exit

  discard_on ActiveJob::DeserializationError

  retry_on_recoverable_exceptions

  sig do
    params(
      pull_request_id: ::Integer,
      head_sha: ::String,
      actor_id: ::Integer,
      entry_destroyed_at: T.nilable(::ActiveSupport::TimeWithZone)
    ).void
  end
  def perform(pull_request_id, head_sha, actor_id, entry_destroyed_at)
    actor = User.find_by(id: actor_id)
    pull_request = PullRequest.find_by(id: pull_request_id)
    repository = pull_request&.repository

    unless repository&.feature_enabled?(:merge_queue_cancel_checksuite_on_destroy)
      GitHub.logger.info("MergeQueueCancelCheckSuiteJob: disabled by feature flag", repository_id: repository&.id)
      return
    end

    return GitHub.logger.info("missing entry_destroyed_at argument") unless entry_destroyed_at

    GitHub.logger.with_named_tags(
      "code.namespace": "MergeQueueCancelCheckSuiteJob",
      "code.function": "perform",
      "gh.repo.id": repository.id,
      "gh.actor.id": actor_id,
      "gh.pull_request.id": pull_request_id,
      "gh.merge_queue.head_sha": head_sha
    ) do
      unless actor && pull_request && repository
        GitHub.logger.error("missing user, pull_request, or repo")
        return
      end

      # Find any checksuites for the head sha which has been destroyed
      # Skip checksuites which where started after the item was removed from the queue to avoid race conditions
      pagination = GH::Pagination::Offset.new(page: 1, per_page: 1000)
      check_suites_collection = Checks.domain.check_suites.for_head_sha_created_before(
        repo: repository,
        head_sha: head_sha,
        time: entry_destroyed_at,
        pagination:
      )

      check_suites_collection = Checks.domain.check_suites.prefetch(check_suites_collection, [:workflow_run])
      check_suites_offset_collection = T.cast(check_suites_collection, GH::Domain::OffsetCollection[CheckSuite])

      if check_suites_offset_collection.total_pages > 1
        # To prevent this job putting unnecessary load, set the upper limit at 1000 check_suites to look at
        # if there are more than 1000 check_suites, lets bail out to be on the safe side
        GitHub.logger.info(
          "more than 1000 check suites found, bailing out",
           count: check_suites_offset_collection.total_entries
        )
        return
      end

      unless check_suites_collection.any?
        GitHub.logger.info("no check suites found")
        return
      end

      # Loop through the cancelable check suites and cancel them
      check_suites_collection.each do |check_suite|
        # Checks that it's a workflow / action and in state to be canceled
        unless check_suite.cancelable?
          GitHub.logger.info("check suite not cancelable", check_suite_id: check_suite.id)
          next
        end

        unless check_suite.workflow_run&.event == "merge_group"
          GitHub.logger.info("check suite not part of a merge group", check_suite_id: check_suite.id)
          next
        end

        GitHub.logger.info("canceling check suite", check_suite_id: check_suite.id)
        GitHub.dogstats.increment("merge_queue.cancel_check_suite.entry_destroyed")

        with_write do
          result = check_suite.cancel(actor:)
          GitHub.logger.info("canceled result",
             check_suite_id: check_suite.id,
             succeeded: result.call_succeeded?,
             status: result.status,
             value: result.value,
          )
        end
      end
    end
  end
end
