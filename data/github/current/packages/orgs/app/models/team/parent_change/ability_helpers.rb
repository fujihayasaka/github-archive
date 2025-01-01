# typed: true
# frozen_string_literal: true
module Team::ParentChange
  # TODO: Extract the queries in this module into Authorization::Service
  module AbilityHelpers

    extend ActiveSupport::Concern

    BATCH_SIZE = Ability::BATCH_SIZE

    # Internal
    #
    # Returns a list of tuples, in the form [abilities.id, abilities.actor_id]
    # for the direct abilities from users to the teams with the given team_ids.
    #
    def direct_abilities(team_ids)
      return [] if team_ids.blank?
      ActiveRecord::Base.connected_to(role: :reading) do
        sql = Arel.sql(<<-SQL, subject_ids: team_ids, direct: Ability.priorities[:direct])
          SELECT id, actor_id
          FROM abilities
          WHERE priority = :direct
          AND actor_type = 'User'
          AND subject_type = 'Team'
          AND subject_id IN (:subject_ids)
        SQL

        Ability.connection.select_rows(sql)
      end
    end

    # Internal
    #
    # Returns the list of ids for indirect abilities from users to teams, which parent
    # is in the given list of parent_ids, and its subject is in the given list of subject_ids
    #
    # parent_ids is optional, if not provided abilities won't be filtered by parent.
    #
    def indirect_ability_ids(subject_ids, parent_ids: :all)
      return [] if subject_ids.blank?
      ActiveRecord::Base.connected_to(role: :reading) do
        sql = Arel.sql(<<-SQL, subject_ids: subject_ids, indirect: Ability.priorities[:indirect])
          SELECT id
          FROM abilities
          WHERE priority = :indirect
          AND actor_type = 'User'
          AND subject_type = 'Team'
          AND subject_id IN (:subject_ids)
        SQL

        sql += Arel.sql(<<-SQL, parent_ids: parent_ids) if parent_ids != :all
          AND parent_id IN (:parent_ids)
        SQL

        Ability.connection.select_values(sql)
      end
    end

    # Internal
    #
    # Destroys the abilities with the given ability_ids
    #
    # Returns the rows deleted
    #
    def delete(ability_ids)
      return 0 if ability_ids.blank?
      rows_deleted = 0

      ability_ids.each_slice(BATCH_SIZE) do |ids|
        sql = Arel.sql(<<-SQL, ids: ids)
          DELETE FROM abilities
          WHERE id IN (:ids)
        SQL

        affected_rows = Ability.throttle { Ability.connection.delete(sql) }

        rows_deleted += affected_rows
      end

      GitHub.dogstats.distribution "ability.revoked.indirect_ancestors.dist", rows_deleted
      rows_deleted
    end

    # Internal
    #
    # Given a list of tuples, each of which is of type ([ability_id, actor_id], subject_id)
    # It creates new materialized indirect abilities.
    #
    # Returns the rows created
    #
    def create(tuples)
      return 0 if tuples.blank?
      rows_inserted = 0

      tuples.each_slice(BATCH_SIZE) do |batch|
        rows = batch.map do |((parent_id, actor_id), subject_id)|
          [
            actor_id,
            "User",
            Ability.actions[:read],
            subject_id,
            "Team",
            Ability.priorities[:indirect],
            parent_id,
            GitHub::SQL::ArelLiterals::NOW,
            GitHub::SQL::ArelLiterals::NOW,
          ]
        end

        sql = Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(rows))
          INSERT IGNORE INTO abilities
          (actor_id, actor_type, action, subject_id, subject_type,
           priority, parent_id, created_at, updated_at)
          :rows
        SQL

        Ability.throttle { Ability.connection.insert(sql) }

        rows_inserted += batch.size
      end

      GitHub.dogstats.distribution "ability.granted.indirect_ancestors.dist", rows_inserted
      rows_inserted
    end
  end
end
