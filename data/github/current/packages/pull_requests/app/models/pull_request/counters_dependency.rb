# typed: true
# frozen_string_literal: true

module PullRequest::CountersDependency
  extend T::Sig
  extend T::Helpers

  requires_ancestor { PullRequest }

  # Public: Updated the `reviews_with_body_count` column on the table
  sig { void }
  def update_review_count
    GitHub.dogstats.time("pull_request", tags: %W[action:update_counters model:pull_request_reviews]) do
      # NOTE: This is deliberately two separate queries. Making the SELECT
      # a sub-query of the UPDATE would be slightly more efficient, but the
      # access order leads to deadlocks.
      count = reviews.where(repository_id:).submitted.has_body.count(:id)
      PullRequest.where(id:, repository_id:).update_all(reviews_with_body_count: count)
    end
  end

  def update_review_and_comment_counts
    reviews_with_body_count = reviews.where(repository_id:).submitted.has_body.count(:id)
    review_comments_with_body_count = review_comments.where(repository_id:).submitted.where(has_body: true).count(:id)

    PullRequest.where(id:, repository_id:).update_all(reviews_with_body_count:, review_comments_with_body_count:)
  end

  # Public: Updated the `review_comments_with_body_count` column on the pull_requests table
  sig { void }
  def update_review_comments_count
    GitHub.dogstats.time("pull_request", tags: %W[action:update_counters model:pull_request_review_comments]) do
      # NOTE: This is deliberately two separate queries. Making the SELECT
      # a sub-query of the UPDATE would be slightly more efficient, but the
      # access order leads to deadlocks.
      count = review_comments.where(repository_id:).submitted.has_body.count(:id)
      PullRequest.where(id:, repository_id:).update_all(review_comments_with_body_count: count)
    end
  end
end
