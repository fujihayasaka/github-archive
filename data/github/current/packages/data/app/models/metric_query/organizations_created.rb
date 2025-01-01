# typed: true
# frozen_string_literal: true

class MetricQuery::OrganizationsCreated < MetricQuery
  include MetricQuery::SingleModelColumn

  self.model = Organization

  def all
    relation
      .where.not(login: GitHub.trusted_oauth_apps_org_name)
      .bucketed_by(fully_qualified_column, timespan)
      .count
  end
end
