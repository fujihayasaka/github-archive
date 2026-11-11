# typed: true
# frozen_string_literal: true

class MetricQuery::PullRequestCommentsCreated < MetricQuery
  include MetricQuery::SingleModelColumn

  self.model = IssueComment
  self.display_name = "Comments"

  def all
    relation
      .joins(:issue).where.not(issues: { pull_request_id: nil })
      .for_owner(@params[:owner_id])
      .bucketed_by(fully_qualified_column, timespan)
      .count # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end
end
