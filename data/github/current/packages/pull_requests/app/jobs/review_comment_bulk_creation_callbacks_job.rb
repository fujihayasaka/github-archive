# typed: true
# frozen_string_literal: true

class ReviewCommentBulkCreationCallbacksJob < ApplicationJob
  queue_as :pull_request_review_comment_callbacks

  retry_on_dirty_exit

  def perform(pull_request_review:)
    return unless GitHub.flipper[:async_pr_review_comment_callbacks].enabled?(pull_request_review.user)

    comments = pull_request_review.review_comments.to_a
    with_write do
      comments.each(&:after_commit_on_create_callbacks)
    end
  end
end
