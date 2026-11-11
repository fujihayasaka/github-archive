# typed: true
# frozen_string_literal: true

class ReviewThreadReplier
  class PullRequestReviewMissingError < StandardError
  end

  def initialize(
    review:,
    parent:,
    body:,
    user:,
    single_comment: false
  )

    raise PullRequestReviewMissingError, "Missing review" unless review

    @review = review
    @parent = parent
    @body = body
    @user = user
    @single_comment = single_comment
  end

  def create_reply_comment
    thread = parent.pull_request_review_thread
    comment = thread.build_reply(pull_request_review: review, user: user, body: body)

    if comment.save!
      review.comment! if single_comment
      comment.reload
    end

    comment
  end

  private

  attr_reader :review, :parent, :body, :user, :single_comment
end
