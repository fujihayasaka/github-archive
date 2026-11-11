# typed: strict
# frozen_string_literal: true

module EnterpriseTeamMigrationJobHelpers
  extend T::Helpers

  requires_ancestor { ApplicationJob }

  sig { params(business: Business, enterprise_team_ids: T.nilable(T::Array[Integer])).returns(ActiveRecord::Relation) }
  def teams_scope(business:, enterprise_team_ids:)
    teams = EnterpriseTeam.unscoped.owned_by(business)
    return teams unless enterprise_team_ids&.any?

    teams.where(id: enterprise_team_ids)
  end
end
