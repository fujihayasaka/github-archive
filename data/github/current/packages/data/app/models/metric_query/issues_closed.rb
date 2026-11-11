# typed: true
# frozen_string_literal: true

class MetricQuery::IssuesClosed < MetricQuery
  include MetricQuery::SingleModelColumn

  self.model = Issue
  self.column = :closed_at

  def all
    relation.where(pull_request_id: nil)
      .for_owner(@params[:owner_id])
      .bucketed_without_group(fully_qualified_column, timespan)
      .tally_by_creation_date
  end
end
