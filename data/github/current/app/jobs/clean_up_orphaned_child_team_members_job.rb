# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Sweeps orphaned indirect ("child team member") `Ability` rows from a single
# team. Backstop for the bug fixed in #432887 / PCR 2025-12-22, in which a
# team re-parenting left `priority: indirect` rows behind that pointed at a
# parent ability whose subject team was no longer in the team's descendant
# tree -- surfacing users as "child team member" of a team that no longer
# inherits any membership from those former descendants.
#
# An ability row is considered orphaned when **all** of the following hold:
#
# * `actor_type = User`, `subject_type = Team`, `subject_id = team.id`,
#   `priority = indirect`.
# * Its `parent_id` ability is missing, has a non-Team subject, or has a
#   subject team that is no longer a descendant of `team`. (An indirect row
#   on T should always have a parent ability on a current descendant of T --
#   that is the invariant the post-fix codebase maintains.)
#
# Direct ability rows are never touched, so a user who has both a direct and
# an orphaned indirect row keeps their direct membership.
#
# Only enqueued from `Stafftools::TeamsController#clean_up_orphaned_child_team_members`.
class CleanUpOrphanedChildTeamMembersJob < ApplicationJob
  queue_as :clean_up_orphaned_child_team_members
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  BATCH_SIZE = Ability::BATCH_SIZE

  # Public: number of orphaned indirect "child team member" ability rows on
  # `team`. Used by the stafftools team members page to decide whether to
  # surface the cleanup banner and how many records to mention.
  def self.orphaned_count(team)
    descendant_ids = team.descendant_ids
    Ability.connection.select_value(orphaned_scope_sql(team.id, descendant_ids, select: "COUNT(*)")).to_i
  end

  # Internal: builds the SELECT used by both the count helper and the
  # batched ID lookup in `perform`. Kept on the class so the controller and
  # the job agree on the definition of "orphan".
  def self.orphaned_scope_sql(team_id, descendant_ids, select:)
    if descendant_ids.empty?
      # No descendants left -- every indirect User->Team ability on this
      # team is orphaned by definition.
      Arel.sql(<<~SQL, team_id: team_id, indirect: Ability.priorities[:indirect])
        SELECT #{select}
        FROM abilities a
        WHERE a.subject_type = 'Team'
        AND a.subject_id = :team_id
        AND a.actor_type = 'User'
        AND a.priority = :indirect
      SQL
    else
      # Some descendants remain -- an indirect row is orphan only when its
      # parent ability points at a team that is no longer a descendant.
      Arel.sql(<<~SQL, team_id: team_id, indirect: Ability.priorities[:indirect], descendant_ids: descendant_ids)
        SELECT #{select}
        FROM abilities a
        LEFT JOIN abilities p ON a.parent_id = p.id
        WHERE a.subject_type = 'Team'
        AND a.subject_id = :team_id
        AND a.actor_type = 'User'
        AND a.priority = :indirect
        AND (p.id IS NULL OR p.subject_type != 'Team' OR p.subject_id NOT IN (:descendant_ids))
      SQL
    end
  end

  # Public: Sweep orphaned indirect User->Team abilities for `team_id`.
  #
  # team_id  - Integer team id.
  # actor_id - Optional Integer id of the staff user who triggered the sweep.
  #            Accepted for API symmetry with the controller; currently
  #            unused.
  def perform(team_id, actor_id: nil)
    team = Team.where(id: team_id, deleted: false).first
    return unless team

    descendant_ids = team.descendant_ids

    with_write do
      loop do
        ids = orphaned_ability_ids(team.id, descendant_ids, limit: BATCH_SIZE)
        break if ids.empty?

        affected = Ability.throttle do
          Ability.connection.delete(
            Arel.sql(<<~SQL, ids: ids),
              DELETE FROM abilities
              WHERE id IN (:ids)
            SQL
          )
        end

        # `affected == 0` guards against replica lag re-serving IDs we
        # already deleted (the SELECT runs against a reader, the DELETE
        # against the writer); without this the loop could spin until the
        # replica catches up.
        break if affected == 0 || ids.size < BATCH_SIZE
      end
    end
  end

  private

  def orphaned_ability_ids(team_id, descendant_ids, limit:)
    sql = self.class.orphaned_scope_sql(team_id, descendant_ids, select: "a.id")
    sql += Arel.sql(" LIMIT #{limit.to_i}")
    Ability.connection.select_values(sql)
  end
end
