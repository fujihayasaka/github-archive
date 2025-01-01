# typed: true
# frozen_string_literal: true

class MetricQuery::PullRequestReviewsCreated < MetricQuery
  include MetricQuery::SingleModelColumn

  self.model = PullRequestReview
  self.display_name = "Code Review"

  def all
    relation
      .for_owner(@params[:owner_id], { pull_request: :repository }, repo_filter_key: "pull_requests.repository_id")
      .bucketed_without_group(fully_qualified_column, timespan)
      .tally_by_creation_date
  end
end
