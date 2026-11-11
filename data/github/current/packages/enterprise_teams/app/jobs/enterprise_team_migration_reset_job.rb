# typed: true
# frozen_string_literal: true

class EnterpriseTeamMigrationResetJob < ApplicationJob
  include EnterpriseTeamMigrationJobHelpers

  queue_as :enterprise_team_migration
  retry_on_dirty_exit

  sig { params(business: Business, enterprise_team_ids: T.nilable(T::Array[Integer])).void }
  def perform(business:, enterprise_team_ids: nil)
    team_ids = teams_scope(business: business, enterprise_team_ids: enterprise_team_ids).pluck(:id)
    return if team_ids.empty?

    failures = T.let([], T::Array[String])

    EnterpriseTeamMigration
      .where(enterprise_team_id: team_ids)
      .where.not(migration_status: :completed)
      .preload(:business_team)
      .find_each do |migration|
        migration.reset!
      rescue => e
        GitHub.logger.error(
          "EnterpriseTeamMigrationResetJob failed",
          exception: e,
          business_id: business.id,
          migration_id: migration.id,
        )
        failures << migration.id.to_s
      end

    if failures.any?
      raise "EnterpriseTeamMigrationResetJob encountered failures for #{failures.size} migration(s): #{failures.join(', ')}"
    end
  end
end
