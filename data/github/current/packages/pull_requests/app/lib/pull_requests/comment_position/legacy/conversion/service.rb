# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Legacy::Conversion
      class Service
        Collection = T.type_alias { T::Hash[PullRequestReviewThread, Positions] }

        # Determine the legacy positional data for a single PullRequestReviewThread synchronously.
        sig { params(pull_request: PullRequest, thread: PullRequestReviewThread).returns(T.nilable(Positions)) }
        def self.for_thread(pull_request:, thread:)
          new(pull_request:, threads: [thread]).call[thread]
        end

        sig do
          params(
            pull_request: PullRequest,
            threads: T::Array[PullRequestReviewThread],
            diff: T.nilable(GitHub::Diff)
          ).void
        end
        def initialize(pull_request:, threads:, diff: nil)
          @pull_request = pull_request
          @threads = threads
          @diff = diff
        end

        sig { returns(Promise[Collection]) }
        def async
          batched_data = Promise.all(
            @threads.flat_map do |thread|
              [
                Promise.resolve(thread),
                thread.async_start_line(@diff),
                thread.async_end_line(@diff),
                thread.async_start_and_end_path(@diff),
              ]
            end
          ).then do |thread_data|
            collection = {}

            thread_data.each_slice(4) do |review_thread, start_line, end_line, (start_path, end_path)|
              collection[review_thread] = Processor.new(
                side: review_thread.side,
                start_side: review_thread.start_side,
                subject_type: review_thread.subject_type&.to_sym,
                base_sha: @diff&.base_sha || @pull_request.base_sha,
                base_path: start_path,
                head_sha: @diff&.sha2 || review_thread.commit_id,
                head_path: end_path,
                start_line_numbers: [start_line&.left, start_line&.right],
                end_line_numbers: [end_line&.left, end_line&.right],
                outdated: review_thread.outdated,
              ).call
            end

            collection
          end
        end

        sig { returns(Collection) }
        def call
          async.sync
        end
      end
    end
  end
end
