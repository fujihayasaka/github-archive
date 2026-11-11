# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ThreadPreviewPositioning
  class Loader
    include GitHub::ResilienceMixin

    MAX_CONTEXT_LINES = 3

    class PositionedThread < T::Struct
      const :thread_id, Integer
      const :diff_lines, T::Array[T::Hash[Symbol, T.untyped]]
      const :end_diff_side, T.nilable(String)
      const :end_line, T.nilable(Integer)
      const :path, T.nilable(String)
      const :start_diff_side, T.nilable(String)
      const :start_line, T.nilable(Integer)
      const :commit_oid, T.nilable(String)
      const :is_outdated, T::Boolean
    end

    sig do
      params(
        threads: T::Array[PullRequestReviewThread],
        pull_request: PullRequest,
        max_context_lines: Integer
      ).returns(T::Array[PositionedThread])
    end
    def self.load(threads:, pull_request:, max_context_lines: MAX_CONTEXT_LINES)
      new(threads:, pull_request:, max_context_lines:).load
    end

    sig do
      params(
        threads: T::Array[PullRequestReviewThread],
        pull_request: PullRequest,
        max_context_lines: Integer
      ).void
    end
    def initialize(threads:, pull_request:, max_context_lines: MAX_CONTEXT_LINES)
      @threads = threads
      @pull_request = pull_request
      @max_context_lines = max_context_lines
    end

    sig { returns(T::Array[PositionedThread]) }
    def load
      with_database_error_fallback(fallback: []) do
        GitHub::PrefillAssociations.prefill_batch_method(@threads, :prelude_new_comment_positioning, @pull_request)
        GitHub::PrefillAssociations.prefill_batch_method(
          @threads,
          :prelude_diff_lines_outside_diff,
          @pull_request,
          { max_context_lines: @max_context_lines, cache_only: false }
        )

        @threads.map do |thread|
          result = thread.prelude_new_comment_positioning(@pull_request)

          # If we can't get positioning, mark as outdated
          if result.nil? || result.is_a?(PullRequests::CommentPosition::Errors)
            next unpositionable_thread(thread)
          end

          # Compute is_outdated solely from result.positioning
          current_position = result.positioning
          is_outdated = current_position.nil? ||
                        current_position.is_a?(PullRequests::CommentPosition::Positions::Indeterminate) ||
                        current_position.is_a?(PullRequests::CommentPosition::Positions::Errored)

          # Select position data source: prefer original_positioning if valid, else fall back to positioning
          position = result.original_positioning
          valid_position = position.is_a?(PullRequests::CommentPosition::Positions::Line) ||
                           position.is_a?(PullRequests::CommentPosition::Positions::Multiline) ||
                           position.is_a?(PullRequests::CommentPosition::Positions::File)
          unless valid_position
            position = current_position
          end

          # If position is not a valid type, mark as outdated and return stub
          unless position.is_a?(PullRequests::CommentPosition::Positions::Line) ||
                 position.is_a?(PullRequests::CommentPosition::Positions::Multiline) ||
                 position.is_a?(PullRequests::CommentPosition::Positions::File)
            next unpositionable_thread(thread)
          end

          # Extract positioning data based on type
          path = nil
          start_line = nil
          start_diff_side = nil
          end_line = nil
          end_diff_side = nil
          commit_oid = nil

          case position
          when PullRequests::CommentPosition::Positions::Line
            path = position.path
            end_line = position.line
            end_diff_side = position.commit_oid == position.base_commit_oid ? "LEFT" : "RIGHT"
            commit_oid = position.commit_oid
          when PullRequests::CommentPosition::Positions::Multiline
            path = position.end_path
            start_line = position.start_line
            start_diff_side = position.start_commit_oid == position.base_commit_oid ? "LEFT" : "RIGHT"
            end_line = position.end_line
            end_diff_side = position.end_commit_oid == position.base_commit_oid ? "LEFT" : "RIGHT"
            commit_oid = position.end_commit_oid
          when PullRequests::CommentPosition::Positions::File
            path = position.path
            commit_oid = position.commit_oid
            # File-level comments don't have line numbers
          end

          PositionedThread.new(
            thread_id: thread.id,
            diff_lines: thread.prelude_diff_lines_outside_diff(@pull_request, { max_context_lines: @max_context_lines, cache_only: false }) || [],
            end_diff_side: end_diff_side,
            end_line: end_line,
            path: path,
            start_diff_side: start_diff_side,
            start_line: start_line,
            commit_oid: commit_oid,
            is_outdated: is_outdated
          )
        end
      end
    end

    private

    sig { params(thread: PullRequestReviewThread).returns(PositionedThread) }
    def unpositionable_thread(thread)
      PositionedThread.new(
        thread_id: thread.id,
        diff_lines: [],
        end_diff_side: nil,
        end_line: nil,
        path: thread.path,
        start_diff_side: nil,
        start_line: nil,
        commit_oid: nil,
        is_outdated: true
      )
    end
  end
end
