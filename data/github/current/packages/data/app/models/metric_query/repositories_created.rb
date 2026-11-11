# typed: true
# frozen_string_literal: true

class MetricQuery::RepositoriesCreated < MetricQuery
  include MetricQuery::SingleModelColumn

  self.model = Repository

  def all
    relation.where(@params.slice(:owner_id))
      .bucketed_by(fully_qualified_column, timespan)
      .count
  end
end
