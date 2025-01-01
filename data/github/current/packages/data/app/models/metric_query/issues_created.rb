# typed: true
# frozen_string_literal: true

class MetricQuery::IssuesCreated < MetricQuery
  include MetricQuery::SingleModelColumn

  self.model = Issue
  self.display_name = "Issues"

  def all
    relation.where(pull_request_id: nil)
      .for_owner(@params[:owner_id])
      .bucketed_without_group(fully_qualified_column, timespan)
      .tally_by_creation_date
  end
end
