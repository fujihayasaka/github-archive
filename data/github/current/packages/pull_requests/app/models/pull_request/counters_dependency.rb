# typed: true
# frozen_string_literal: true

module PullRequest::CountersDependency
  extend T::Helpers

  requires_ancestor { PullRequest }

  sig { void }
  def update_review_and_comment_counts
    local_reviews_count = reviews.where(repository_id:).submitted.has_body.count(:id)
    local_comments_count = review_comments.where(repository_id:).submitted.where(has_body: true).count(:id)

    if FeatureFlag.vexi.enabled?(:prs_counters_dependency_query_change, repository, default: false)
      if reviews_with_body_count != local_reviews_count &&
        review_comments_with_body_count != local_comments_count
        GitHub.dogstats.distribution_time("pull_request.counters_dependency",
          tags: %W[action:update_review_and_comment_counts model:pull_request_review_comments query:update_all]) do
          update_columns(
            reviews_with_body_count: local_reviews_count,
            review_comments_with_body_count: local_comments_count)
        end
      elsif reviews_with_body_count != local_reviews_count
        GitHub.dogstats.distribution_time("pull_request.counters_dependency",
          tags: %W[action:update_review_and_comment_counts model:pull_request_review_comments query:update_reviews]) do
          update_column(:reviews_with_body_count, local_reviews_count)
        end
      elsif review_comments_with_body_count != local_comments_count
        GitHub.dogstats.distribution_time("pull_request.counters_dependency",
          tags: %W[action:update_review_and_comment_counts model:pull_request_review_comments query:update_comments]) do
          update_column(:review_comments_with_body_count, local_comments_count)
        end
      end
    else
      GitHub.dogstats.distribution_time("pull_request.counters_dependency",
        tags: %W[action:update_review_and_comment_counts model:pull_request_review_comments query:update_all]) do
        PullRequest.where(id:, repository_id:).update_all(
          reviews_with_body_count: local_reviews_count,
          review_comments_with_body_count: local_comments_count
        )
      end
    end
  end

  # Public: Updated the `review_comments_with_body_count` column on the pull_requests table
  sig { void }
  def update_review_comments_count
    # NOTE: This is deliberately two separate queries. Making the SELECT
    # a sub-query of the UPDATE would be slightly more efficient, but the
    # access order leads to deadlocks.
    local_comments_count = review_comments.where(repository_id:).submitted.has_body.count(:id)

    if FeatureFlag.vexi.enabled?(:prs_counters_dependency_query_change, repository, default: false)
      if review_comments_with_body_count != local_comments_count
        GitHub.dogstats.distribution_time("pull_request.counters_dependency",
          tags: %W[action:update_review_comments_count model:pull_request_review_comments query:update_comments]) do
          update_column(:review_comments_with_body_count, local_comments_count)
        end
      end
    else
      GitHub.dogstats.distribution_time("pull_request.counters_dependency",
      tags: %W[action:update_review_comments_count model:pull_request_review_comments query:update_comments]) do
        PullRequest.where(id:, repository_id:).update_all(review_comments_with_body_count: local_comments_count)
      end
    end
  end
end
