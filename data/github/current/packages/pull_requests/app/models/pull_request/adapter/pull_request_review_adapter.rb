# typed: true
# frozen_string_literal: true

class PullRequest::Adapter::PullRequestReviewAdapter < Issue::Adapter::Base
  PULL_REQUEST_REVIEW = "PullRequestReview"

  attr_reader :pull_request, :pull_request_review, :id

  def initialize(context, pull_request_review_id:)
    super(context)
    @pull_request = context.pull_request
    @pull_request_review = context.reviews_by_id[pull_request_review_id] || PullRequestReview.find_by(id: pull_request_review_id)
    if !@pull_request_review && GitHub.flipper[:log_missing_reviews].enabled?
      GitHub.logger.error(
        "gh.pull_request.review_id" => pull_request_review_id,
        "gh.pull_request.reviews_by_id" => context.reviews_by_id,
        "gh.pull_request.id" => @pull_request.id,
        "gh.viewer_id" => context.viewer&.id,
      )
      @invalid = true
      return
    end
    @id = pull_request_review.global_relay_id
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
