# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Files::ReviewMenu
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

    class CommentPreview < T::Struct
      const :body_html, String
      const :id, String
      const :is_outdated, T::Boolean
      const :is_resolved, T::Boolean
      const :line, T.nilable(Numeric)
      const :path, String
      const :subject, ThreadSubject
      const :subject_type, String
      const :thread_comments, T::Array[PullRequestReviewComment]
    end

    class PendingReview < T::Struct
      # If there is no pending review for the user, this is nil and the comments are empty
      const :review, T.nilable(PullRequestReview)
      const :review_comments, T::Array[CommentPreview]
    end

    sig do
      params(
        current_user: T.nilable(User),
        pull_request: ::PullRequest,
        cap_filter: T.nilable(ConditionalAccess::Web::Filter)
      ).returns(PendingReview)
    end
    def self.load(current_user:, pull_request:, cap_filter: nil)
      new(current_user:, pull_request:, cap_filter:).load
    end

    sig do
      params(
        current_user: T.nilable(User),
        pull_request: ::PullRequest,
        cap_filter: T.nilable(ConditionalAccess::Web::Filter)
      ).void
    end
    def initialize(current_user:, pull_request:, cap_filter: nil)
      @current_user = current_user
      @pull_request = pull_request
      @cap_filter = cap_filter
    end

    sig { returns(PendingReview) }
    def load
      empty_pending_review = PendingReview.new(
        review: nil,
        review_comments: []
      )

      return empty_pending_review if @current_user.nil?

      pending_review = @pull_request.latest_pending_review_for(@current_user)

      body_html_context = {
        viewer: @current_user,
        cap_filter: @cap_filter,
        unfurl_references: true,
      }

      return empty_pending_review unless pending_review.present?

      comment_promises = pending_review.review_comments.map do |comment|
        comment.memoized_async_pull_request_review_thread.then do |thread|
          subject_promises = [
            with_async_database_error_fallback(comment.async_body_html(context: body_html_context), fallback: ""),
            thread.async_diff_lines(max_context_lines: MAX_CONTEXT_LINES),
            thread.async_diff_side,
            thread.async_end_line,
            thread.async_original_line,
            thread.async_original_start_line,
            thread.async_start_line,
            thread.async_start_side
          ]

          Promise.all(subject_promises).then do |body_html, diff_lines, end_side, end_line, original_end_line, original_start_line, start_line, start_side|
            CommentPreview.new(
              body_html: body_html,
              id: String(thread.id),
              is_outdated: thread.outdated?,
              is_resolved: thread.resolved?,
              line: thread.line,
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
      end

      PendingReview.new(
        review: pending_review,
        review_comments: Promise.all(comment_promises).sync
      )
    end
  end
end
