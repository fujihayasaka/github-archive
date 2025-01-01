# typed: true
# frozen_string_literal: true

class MetricQuery::PullRequestsMerged < MetricQuery
  include MetricQuery::SingleModelColumn

  self.model = PullRequest
  self.column = :merged_at

  def all
    relation
      .for_owner(@params[:owner_id])
      .bucketed_without_group(fully_qualified_column, timespan)
      .tally_by_creation_date
  end
end
