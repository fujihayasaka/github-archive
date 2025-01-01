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

    class CommentPreview < T::Struct
      const :thread_id, String
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
          CommentPreview.new(thread_id: String(thread.id))
        end
      end

      PendingReview.new(
        review: pending_review,
        review_comments: Promise.all(comment_promises).sync
      )
    end
  end
end
