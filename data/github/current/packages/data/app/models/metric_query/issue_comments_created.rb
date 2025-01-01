# typed: true
# frozen_string_literal: true

class MetricQuery::IssueCommentsCreated < MetricQuery
  include MetricQuery::SingleModelColumn

  self.model = IssueComment
  self.display_name = "Comments"

  def all
    relation
      .for_owner(@params[:owner_id])
      .bucketed_by(fully_qualified_column, timespan)
      .count
  end
end
