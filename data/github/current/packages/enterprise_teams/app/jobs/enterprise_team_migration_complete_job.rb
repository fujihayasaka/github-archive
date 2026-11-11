# typed: true
# frozen_string_literal: true

class EnterpriseTeamMigrationCompleteJob < ApplicationJob
  include EnterpriseTeamMigrationJobHelpers

  queue_as :enterprise_team_migration
  retry_on_dirty_exit

  sig { params(business: Business, enterprise_team_ids: T.nilable(T::Array[Integer])).void }
  def perform(business:, enterprise_team_ids: nil)
    team_ids = teams_scope(business: business, enterprise_team_ids: enterprise_team_ids).pluck(:id)
    return if team_ids.empty?

    migrations = EnterpriseTeamMigration
      .where(enterprise_team_id: team_ids, migration_status: :dual_write)
      .preload(:enterprise_team, :business_team)
      .to_a
    return if migrations.empty?

    repointed = T.let([], T::Array[EnterpriseTeamMigration])

    begin
      # Repoint all seats from ET to BT assignments
      migrations.each do |migration|
        migration.repoint_copilot_seats!(T.must(migration.enterprise_team))
        repointed << migration
      end

      # Finalize all migrations in a single transaction
      EnterpriseTeamMigration.with_write do
        EnterpriseTeamMigration.transaction do
          migrations.each do |migration|
            migration.completed_cleanup!
          end
        end
      end
    rescue => e
      # Rollback: unrepoint all seats that were already repointed
      repointed.each do |migration|
        migration.unrepoint_copilot_seats!(T.must(migration.enterprise_team))
      rescue => rollback_error
        GitHub.logger.error(
          "EnterpriseTeamMigrationCompleteJob rollback failed",
          exception: rollback_error,
          business_id: business.id,
          migration_id: migration.id,
        )
      end

      raise e
    end

    # Ensure all BT seat assignments have seats for their members.
    # This covers cases where the ET converter hadn't run yet to create seats, or where members
    # were added during the dual-write window after the ET converter last ran.
    business_team_ids = migrations.filter_map { |m| m.business_team&.id }
    if business_team_ids.any?
      seat_assignment_ids = Copilot::SeatAssignment.where(owner: business, assignable_type: "BusinessTeam", assignable_id: business_team_ids).pluck(:id)
      seat_assignment_ids.each do |sa_id|
        Copilot::SeatManagement::SeatAssignmentConverterJob.perform_later(seat_assignment_id: sa_id)
      end
    end

    GlobalInstrumenter.instrument("enterprise_team.migration", {
      action: :complete,
      enterprise_id: business.id,
      team_count: migrations.size,
    })

    should_transition_business = with_write { !business.enterprise_teams.exists? }
    EnterpriseTeamMigrationFinalizeBusinessTransitionJob.perform_later(business_id: business.id) if should_transition_business
  end
end
