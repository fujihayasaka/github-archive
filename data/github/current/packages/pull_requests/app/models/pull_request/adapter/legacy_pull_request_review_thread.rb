# typed: true
# frozen_string_literal: true

class PullRequest::Adapter::LegacyPullRequestReviewThread < Issue::Adapter::Base
  LEGACY_PULL_REQUEST_REVIEW_THREAD = "PullRequestReviewThread"

  attr_reader :pull_request_review_thread, :id

  def initialize(context, pull_request_review_thread_id:)
    super(context)
    @pull_request_review_thread = context.legacy_reviews_by_id[pull_request_review_thread_id]
    @id = pull_request_review_thread.global_relay_id
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
