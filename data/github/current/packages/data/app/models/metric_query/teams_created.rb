# typed: true
# frozen_string_literal: true

class MetricQuery::TeamsCreated < MetricQuery
  include MetricQuery::SingleModelColumn

  self.model = Team

  def all
    query = relation.where.not(name: "Owners").or(model.where.not(permission: "admin"))
    query = query.where(organization_id: @params[:owner_id]) if @params[:owner_id].present?
    query.bucketed_by(fully_qualified_column, timespan).count
  end
end
