# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Files::ReviewMenu
  class Payload
    class DiffLine < T::Struct
      const :html, String
      const :left, T.nilable(Numeric)
      const :right, T.nilable(Numeric)
      const :text, String
      const :type, String
    end

    class Author < T::Struct
      const :login, String
      const :avatarUrl, String
    end

    class CommentAuthor < T::Struct
      const :author, T.nilable(Author)
    end

    class CommentPreview < T::Struct
      const :threadId, String
    end

    class PendingReview < T::Struct
      # This is nil when there is no pending review for the user
      const :id, T.nilable(Numeric)
      const :comments, T::Array[CommentPreview]
    end

    sig do
      params(
        pending_review: PullRequests::PageData::Files::ReviewMenu::Loader::PendingReview
      ).returns(PendingReview)
    end
    def self.call(pending_review)
      new.call(pending_review)
    end

    sig do
      params(
        pending_review: PullRequests::PageData::Files::ReviewMenu::Loader::PendingReview
      ).returns(PendingReview)
    end
    def call(pending_review)
      PendingReview.new(
        id: pending_review.review&.id,
        comments: pending_review.review_comments.map do |comment|
          CommentPreview.new(threadId: comment.thread_id)
        end
      )
    end
  end
end
