# typed: true
# frozen_string_literal: true

class EnterpriseTeamMigrationStartJob < ApplicationJob
  include EnterpriseTeamMigrationJobHelpers

  queue_as :enterprise_team_migration
  retry_on_dirty_exit

  sig { params(business: Business, enterprise_team_ids: T.nilable(T::Array[Integer])).void }
  def perform(business:, enterprise_team_ids: nil)
    teams = teams_scope(business: business, enterprise_team_ids: enterprise_team_ids)
    teams.includes(:business).each do |team|
      migration = team.enterprise_team_migration || EnterpriseTeamMigration.start!(team)
      migration.perform_initial_sync
    end
  end
end
