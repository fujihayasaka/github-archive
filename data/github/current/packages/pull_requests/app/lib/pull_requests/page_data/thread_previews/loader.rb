# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ThreadPreviews
  class Loader
    include GitHub::ResilienceMixin

    # Taken from PullRequests::ReviewThreadDiffLinesComponent::MAX_CONTEXT_LINES
    MAX_CONTEXT_LINES = 3

    class DiffSide < T::Enum
      enums do
        RIGHT = new("RIGHT")
        LEFT = new("LEFT")
      end
    end

    class ThreadSubject < T::Struct
      const :diff_lines, T.nilable(T::Array[T::Hash[Symbol, T.untyped]])
      const :end_line, T.nilable(Numeric)
      const :end_diff_side, T.nilable(DiffSide)
      const :original_end_line, T.nilable(Numeric)
      const :original_start_line, T.nilable(Numeric)
      const :pull_request_commit, T.nilable(String)
      const :start_diff_side, T.nilable(DiffSide)
      const :start_line, T.nilable(Numeric)
    end

    class ThreadPreview < T::Struct
      const :first_comment, T.nilable(T::Array[PullRequests::PageData::ThreadComments::Loader::Comment])
      const :line, T.nilable(Numeric)
      const :id, String
      const :is_outdated, T::Boolean
      const :is_resolved, T::Boolean
      const :path, String
      const :subject, ThreadSubject
      const :subject_type, String
      const :thread_comments, T::Array[PullRequestReviewComment]
    end

    class ThreadCounts < T::Struct
      const :path, String
      const :thread_count, Integer
    end

    sig { returns(PullRequest) }
    attr_reader :pull_request

    sig { returns(T.nilable(User)) }
    attr_reader :current_user

    sig { returns(T.nilable(ConditionalAccess::Web::Filter)) }
    attr_reader :cap_filter

    sig do
      params(
        current_user: T.nilable(User),
        pull_request: PullRequest,
        cap_filter: T.nilable(ConditionalAccess::Web::Filter)
      ).returns(T::Array[ThreadPreview])
    end
    def self.load(current_user:, pull_request:, cap_filter: nil)
      new(current_user:, pull_request:, cap_filter:).load
    end

    sig do
      params(
        current_user: T.nilable(User),
        pull_request: PullRequest,
        cap_filter: T.nilable(ConditionalAccess::Web::Filter)
      ).returns(T::Hash[String, Integer])
    end
    def self.load_counts_by_path(current_user:, pull_request:, cap_filter: nil)
      new(current_user:, pull_request:, cap_filter:).load_counts_by_path
    end

    sig { params(current_user: T.nilable(User), pull_request: PullRequest, cap_filter: T.nilable(ConditionalAccess::Web::Filter)).void }
    def initialize(current_user:, pull_request:, cap_filter: nil)
      @current_user = current_user
      @pull_request = pull_request
      @cap_filter = cap_filter
    end

    sig { returns(T::Array[ThreadPreview]) }
    def load
      with_database_error_fallback(fallback: []) do
        threads = pull_request.review_comment_threads_for(current_user)

        promises = threads.map do |thread|
          comment_promise = PullRequests::PageData::ThreadComments::Loader.load_async(
            thread: thread,
            current_user: current_user,
            max_comments: 1,
            cap_filter: cap_filter,
            comment_data_type: PullRequests::PageData::ThreadComments::Loader::CommentDataType::Preview
          )

          thread_promises = [
            comment_promise,
            thread.async_diff_lines(max_context_lines: MAX_CONTEXT_LINES),
            thread.async_diff_side,
            thread.async_end_line,
            thread.async_original_line,
            thread.async_original_start_line,
            thread.async_start_line,
            thread.async_start_side
          ]

          Promise.all(thread_promises).then do |first_comment, diff_lines, end_side, end_line, original_end_line, original_start_line, start_line, start_side|
            ThreadPreview.new(
              first_comment: first_comment,
              line: thread.line,
              id: String(thread.id),
              is_outdated: thread.outdated?,
              is_resolved: thread.resolved?,
              path: thread.path,
              subject_type: thread.subject_type,
              subject: ThreadSubject.new(
                diff_lines: diff_lines,
                end_line: end_line&.position,
                end_diff_side: end_side == :left ? DiffSide::LEFT : DiffSide::RIGHT,
                original_end_line: original_end_line,
                original_start_line: original_start_line,
                pull_request_commit: thread.commit_id,
                start_diff_side: start_side == :left ? DiffSide::LEFT : DiffSide::RIGHT,
                start_line: start_line&.position
              ),
              thread_comments: thread.comments.load_target
            )
          end
        end

        Promise.all(promises).sync
      end
    end

    sig { returns(T::Hash[String, Integer]) }
    def load_counts_by_path
      with_database_error_fallback(fallback: {}) do
        pull_request.review_comment_threads_for(current_user).each_with_object(Hash.new(0)) do |thread, counts|
          counts[thread.path] += 1
        end
      end
    end
  end
end
