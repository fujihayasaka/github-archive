# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Legacy
      # Utility module for converting the legacy positional data in to the new Positions schema. This exists
      # to ensure we don't have to immediately backfill new positional columns and can enable a slow roll out of a
      # new schema.
      module Conversion
        # Convert a collection of Threads' legacy position data to the new Position schema, synchronously.
        sig do
          params(
            pull_request: PullRequest,
            threads: T::Array[PullRequestReviewThread]
          ).returns(Service::Collection)
        end
        def self.for_threads(pull_request:, threads:)
          Service.new(pull_request:, threads:).call
        end

        # Convert a single Thread's legacy position data to the new Position schema, synchronously.
        sig do
          params(
            pull_request: PullRequest,
            thread: PullRequestReviewThread
          ).returns(T.nilable(Positions))
        end
        def self.for_thread(pull_request:, thread:)
          for_threads(pull_request:, threads: [thread])[thread]
        end
      end
    end
  end
end
