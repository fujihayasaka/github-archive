# typed: strict
# frozen_string_literal: true

module PullRequests
  module External
    module Domain
      class StatusChecks < GH::Domain::Base
        # Given a PullRequest, return all of the relevant status checks reported
        # or expected on the head commit, and optionally the merge commit.
        # By default, checks from both the head commit and merge commit are included.
        # Set `include_merge_commit: false` to exclude merge commit checks.
        sig do
          params(
            pull_request: PullRequest,
            preloader: T.nilable(IPreloader),
            viewer: T.nilable(User),
            include_merge_commit: T::Boolean,
          )
            .returns(GH::Domain::Collection[IStatusCheck])
            .checked(:always)
            .on_failure(:raise)
        end
        def for_pull_request(pull_request, preloader: nil, viewer: nil, include_merge_commit: true)
          finder = StatusCheckFinder.new(pull_request, viewer:, include_merge_commit:)
          checks = finder.canonical_checks do |checks|
            preload(checks, preloader)
          end
          GH::Domain::Collection[IStatusCheck].new(checks)
        end

        # Given an array of PullRequests, return all of the relevant status
        # checks reported or expected on their merge commits or head commits.
        sig do
          params(
            pull_requests: T::Array[PullRequest],
            preloader: T.nilable(IPreloader),
          )
            .returns(T::Hash[PullRequest, T::Array[IStatusCheck]])
            .checked(:always)
            .on_failure(:raise)
        end
        def for_pull_requests(pull_requests, preloader: nil)
          StatusCheckFinder.batch_load(pull_requests) do |checks|
            preload(checks, preloader)
          end
        end

        # Give a MergeQueueEntry, return all of the relevant status checks
        # reported or expected on the entry's merge commit.
        sig do
          params(
            merge_queue_entry: MergeQueueEntry,
            preloader: T.nilable(IPreloader),
          )
            .returns(GH::Domain::Collection[IStatusCheck])
            .checked(:always)
            .on_failure(:raise)
        end
        def for_merge_queue_entry(merge_queue_entry, preloader: nil)
          finder = StatusCheckFinder.new(merge_queue_entry)
          checks = finder.canonical_checks do |checks|
            preload(checks, preloader)
          end
          GH::Domain::Collection[IStatusCheck].new(checks)
        end

        # Given an array of MergeQueueEntries, return all of the relevant
        # status checks reported or expected on their merge commits.
        sig do
          params(
            merge_queue_entries: T::Array[MergeQueueEntry],
            preloader: T.nilable(IPreloader),
          )
            .returns(T::Hash[MergeQueueEntry, T::Array[IStatusCheck]])
            .checked(:always)
            .on_failure(:raise)
        end
        def for_merge_queue_entries(merge_queue_entries, preloader: nil)
          StatusCheckFinder.batch_load(merge_queue_entries) do |checks|
            preload(checks, preloader)
          end
        end

        private

        sig do
          params(
            checks: T::Enumerable[T.any(Status, CombinedStatus::CheckRunAdapter)],
            preloader: T.nilable(IPreloader),
          ).void
        end
        def preload(checks, preloader)
          return if preloader.nil?

          statuses = T.let([], T::Array[Status])
          check_runs = T.let([], T::Array[CombinedStatus::CheckRunAdapter])
          checks.each do |check|
            case check
            when Status
              statuses << check
            when CombinedStatus::CheckRunAdapter
              check_runs << check
            else
              T.absurd(check)
            end
          end

          preloader.preload_statuses(statuses) if statuses.any?
          preloader.preload_check_runs(check_runs) if check_runs.any?
        end
      end
    end
  end
end
