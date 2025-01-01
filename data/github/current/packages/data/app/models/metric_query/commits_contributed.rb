# typed: true
# frozen_string_literal: true

class MetricQuery::CommitsContributed < MetricQuery
  include MetricQuery::SingleModelColumn

  self.model = CommitContribution
  self.display_name = "Commits"
  self.column = :committed_date

  def all
    query =
      if @params[:owner_id].present?
        relation.where(repository: Repository.where(@params.slice(:owner_id)).ids)
      else
        relation
      end

    query
      .bucketed_by(fully_qualified_column, timespan)
      .sum(:commit_count)
  end
end
