# typed: strict
# frozen_string_literal: true

module PullRequests
  module External
    module Domain
      class StatusChecks < GH::Domain::Base
        extend T::Sig

        # Given a PullRequest, return all of the relevant status checks reported
        # or expected on the merge commit or head commit.
        sig do
          params(pull_request: PullRequest)
            .returns(GH::Domain::Collection[IStatusCheck])
            .checked(:always)
            .on_failure(:raise)
        end
        def for_pull_request(pull_request)
          finder = StatusCheckFinder.new(pull_request)
          GH::Domain::Collection[IStatusCheck].new(finder.canonical_checks)
        end

        # Given an array of PullRequests, return all of the relevant status
        # checks reported or expected on their merge commits or head commits.
        sig do
          params(
            pull_requests: T::Array[PullRequest],
            block: T.nilable(T.proc.params(arg0: T::Enumerable[T.any(Status, CombinedStatus::CheckRunAdapter)]).void),
          )
            .returns(T::Hash[PullRequest, T::Array[IStatusCheck]])
            .checked(:always)
            .on_failure(:raise)
        end
        def for_pull_requests(pull_requests, &block)
          StatusCheckFinder.batch_load(pull_requests, &block)
        end

        # Give a MergeQueueEntry, return all of the relevant status checks
        # reported or expected on the entry's merge commit.
        sig do
          params(merge_queue_entry: MergeQueueEntry)
            .returns(GH::Domain::Collection[IStatusCheck])
            .checked(:always)
            .on_failure(:raise)
        end
        def for_merge_queue_entry(merge_queue_entry)
          finder = StatusCheckFinder.new(merge_queue_entry)
          GH::Domain::Collection[IStatusCheck].new(finder.canonical_checks)
        end

        # Given an array of MergeQueueEntries, return all of the relevant
        # status checks reported or expected on their merge commits.
        sig do
          params(
            merge_queue_entries: T::Array[MergeQueueEntry],
            block: T.nilable(T.proc.params(arg0: T::Enumerable[T.any(Status, CombinedStatus::CheckRunAdapter)]).void),
          )
            .returns(T::Hash[MergeQueueEntry, T::Array[IStatusCheck]])
            .checked(:always)
            .on_failure(:raise)
        end
        def for_merge_queue_entries(merge_queue_entries, &block)
          StatusCheckFinder.batch_load(merge_queue_entries, &block)
        end
      end
    end
  end
end
