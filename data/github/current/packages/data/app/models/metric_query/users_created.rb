# typed: true
# frozen_string_literal: true

class MetricQuery::UsersCreated < MetricQuery
  include MetricQuery::SingleModelColumn

  self.model = User

  def all
    relation.where(type: "User")
      .where.not(login: GitHub.ghost_user_login)
      .bucketed_by(fully_qualified_column, timespan)
      .count
  end
end
