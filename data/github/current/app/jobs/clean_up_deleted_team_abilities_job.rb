# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This job is run on an offset after a team is deleted, to check for
# any incorrectly remaining abilities for the team and clear them.
class CleanUpDeletedTeamAbilitiesJob < ApplicationJob
  queue_as :clean_up_deleted_team_abilities

  retry_on_dirty_exit

  def perform(team_id)
    to_delete = Ability.connection.select_value(Arel.sql(<<-SQL, team_id: team_id))
      SELECT COUNT(*)
      FROM abilities
      WHERE (
        subject_type = 'Team' AND subject_id = :team_id
      ) OR (
        actor_type = 'Team' AND actor_id = :team_id
      )
    SQL

    GitHub.dogstats.count \
      "clean_up_deleted_team_abilities.abilities_requiring_deletion.count",
      to_delete
    GitHub.logger.info \
      "Found abilities requiring deletion for deleted team", {
        "gh.team.id": team_id,
        "gh.abilities_requiring_deletion": to_delete
      }

    return unless to_delete > 0

    with_write do
      Authorization.service.clear_abilities_for_multiple_participants \
        participant_type: Team,
        participant_ids: team_id
    end
  end
end
