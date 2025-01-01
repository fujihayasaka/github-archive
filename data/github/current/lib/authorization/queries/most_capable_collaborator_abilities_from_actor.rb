# typed: false
# frozen_string_literal: true

require_relative "base_query"

module Authorization
  module Queries
    class MostCapableCollaboratorAbilitiesFromActor < BaseQuery

      attr_reader :actor, :subject_type, :subject_ids, :min_action

      BATCH_SIZE = 1_000

      def initialize(actor:, subject_type:, subject_ids:, min_action: :read)
        @actor = actor
        @subject_type = subject_type
        @subject_ids = Array.wrap(subject_ids)
        @min_action = min_action
      end

      def execute_implementation
        return default_result unless actor.participates?
        return default_result if subject_ids && subject_ids.empty?

        if !actor.is_a?(ScopedIntegrationInstallation) && GitHub.flipper[:batched_most_capable_collaborator_abilities_from_actor].enabled?(actor)
          query_batched_most_capable_collaborator_abilities
        else
          query_most_capable_collaborator_abilities
        end
      end

      private

      def query_batched_most_capable_collaborator_abilities
        # batch the subject_ids to avoid gigantic IN clauses
        # see: https://github.com/github/ecosystem-apps/issues/2022 for more info
        records = []
        GitHub.dogstats.distribution_time("most_capable_collaborator_abilities_from_actor.execute_in_batches.dist") do
          subject_ids.each_slice(BATCH_SIZE) do |subject_ids_slice|
            GitHub.dogstats.increment("most_capable_collaborator_abilities_from_actor.execute_in_batches.count", tags: ["#{actor.id}:#{subject_ids.size}"])
            bindings = {
              actor_id:       actor.ability_id,
              actor_type:     actor.ability_type,
              subject_type:   subject_type,
              subject_ids:    subject_ids_slice,
              direct:         Ability.priorities[:direct],
              indirect:       Ability.priorities[:indirect],
              min_action:     Ability.actions[min_action],
            }
            sql = Arel.sql(<<-SQL, **bindings)
              SELECT id,
                  actor_id, actor_type, action, subject_id, subject_type,
                  priority, created_at, updated_at, parent_id, NULL grandparent_id
                /* abilities-join-audited */
                FROM abilities ab
                WHERE ab.actor_id     = :actor_id
                  AND ab.actor_type   = :actor_type
                  AND ab.subject_type = :subject_type
                  AND ab.subject_id   IN (:subject_ids)
                  AND ab.action       >= :min_action
                  AND ab.priority <= :direct
              SQL

            sql += Arel.sql(<<-SQL, **bindings)
              UNION

              SELECT NULL AS id,
                grandparent.actor_id, grandparent.actor_type,
                parent.action,
                parent.subject_id, parent.subject_type,
                :indirect AS priority, NULL AS created_at, NULL AS updated_at,
                parent.id AS parent_id, grandparent.id AS grandparent_id
              FROM   abilities parent
              JOIN   abilities grandparent
              ON     grandparent.subject_type = parent.actor_type
              AND    grandparent.subject_id   = parent.actor_id
              AND    parent.priority         <= :direct
              AND    grandparent.priority    <= :direct
              AND    parent.action           >= :min_action
              WHERE  grandparent.actor_id     = :actor_id
              AND    grandparent.actor_type   = :actor_type
              AND    parent.subject_type      = :subject_type
              AND    parent.subject_id        IN (:subject_ids)
            SQL

            connection = Ability.connection
            begin
              records += connection.select_all(sql, "Ability loaded via #{self.class.name}")
            rescue SlowQueryLogger::SlowQuery
              GitHub.dogstats.increment("batched_most_capable_collaborator_abilities_from_actor.slow_query.count", tags: ["#{actor.id}:#{subject_ids.size}"])
              raise
            end
          end
          records = most_capables(records)
          records.map do |record|
            Ability.send :instantiate, record
          end
        end
      end

      def query_most_capable_collaborator_abilities
        records = []
        GitHub.dogstats.increment("most_capable_collaborator_abilities_from_actor.subject_ids.count", tags: ["#{actor.id}:#{subject_ids.size}"])
        GitHub.dogstats.distribution_time("most_capable_collaborator_abilities_from_actor.execute_without_batches.dist") do
          bindings = {
            actor_id:       actor.ability_id,
            actor_type:     actor.ability_type,
            subject_type:   subject_type,
            subject_ids:    subject_ids,
            direct:         Ability.priorities[:direct],
            indirect:       Ability.priorities[:indirect],
            min_action:     Ability.actions[min_action],
          }
          sql = Arel.sql(<<-SQL, **bindings)
            SELECT id,
                actor_id, actor_type, action, subject_id, subject_type,
                priority, created_at, updated_at, parent_id, NULL grandparent_id
              /* abilities-join-audited */
              FROM abilities ab
              WHERE ab.actor_id     = :actor_id
                AND ab.actor_type   = :actor_type
                AND ab.subject_type = :subject_type
                AND ab.subject_id   IN (:subject_ids)
                AND ab.action       >= :min_action
                AND ab.priority <= :direct
            SQL

          sql += Arel.sql(<<-SQL, **bindings)
            UNION

            SELECT NULL AS id,
              grandparent.actor_id, grandparent.actor_type,
              parent.action,
              parent.subject_id, parent.subject_type,
              :indirect AS priority, NULL AS created_at, NULL AS updated_at,
              parent.id AS parent_id, grandparent.id AS grandparent_id
            FROM   abilities parent
            JOIN   abilities grandparent
            ON     grandparent.subject_type = parent.actor_type
            AND    grandparent.subject_id   = parent.actor_id
            AND    parent.priority         <= :direct
            AND    grandparent.priority    <= :direct
            AND    parent.action           >= :min_action
            WHERE  grandparent.actor_id     = :actor_id
            AND    grandparent.actor_type   = :actor_type
            AND    parent.subject_type      = :subject_type
            AND    parent.subject_id        IN (:subject_ids)
          SQL

          connection = Ability.connection
          begin
            records = connection.select_all(sql, "Ability loaded via #{self.class.name}")
          rescue SlowQueryLogger::SlowQuery
            GitHub.dogstats.increment("most_capable_collaborator_abilities_from_actor.slow_query.count", tags: ["#{actor.id}:#{subject_ids.size}"])
            raise
          end
        end
        records = most_capables(records)
        records.map do |record|
          Ability.send :instantiate, record
        end
      end

      def most_capables(records)
        return records if records.empty?
        most_capables = {}

        records.each do |record|
          subject_id = record["subject_id"]
          action = record["action"]

          if !most_capables.key?(subject_id) || action > most_capables[subject_id]["action"]
            most_capables[subject_id] = record
          end
        end

        most_capables.values
      end

      def default_result
        []
      end

      def validation_errors
        errors = []

        unless valid_actor?(actor)
          errors << "#{actor} is not a valid actor"
        end

        if subject_type.nil?
          errors << ":subject_type is required"
        end

        unless subject_ids.is_a?(Array)
          errors << "#{subject_ids} has to be an array"
        end

        errors
      end
    end
  end
end
