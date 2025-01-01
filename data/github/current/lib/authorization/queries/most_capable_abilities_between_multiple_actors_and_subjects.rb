# typed: false
# frozen_string_literal: true

require_relative "base_query"

module Authorization
  module Queries
    class MostCapableAbilitiesBetweenMultipleActorsAndSubjects < BaseQuery

      attr_reader :actor_ids, :actor_type, :subjects, :subject_type, :subject_ids

      def initialize(actor_ids:, actor_type:, subjects:, subject_type:)
        @actor_ids = Array.wrap(actor_ids)
        @actor_type = actor_type
        @subjects = subjects
        @subject_ids = subjects.map(&:id)
        @subject_type = subject_type
      end

      def execute_implementation
        return default_result if actor_ids.empty?
        return default_result if subject_ids.empty?

        direct_and_indirect_abilities
      end

      def direct_and_indirect_abilities
        select_most_capable_abilities(org_admin_abilities + direct_abilities)
      end

      def direct_abilities
        sql_bindings = {
          actor_ids: actor_ids,
          actor_type: actor_type,
          subject_type: subject_type,
          subject_ids: subject_ids,
          direct: Ability.priorities[:direct],
          indirect: Ability.priorities[:indirect],
        }
        sql = Arel.sql <<-SQL, **sql_bindings
        SELECT id,
            actor_id, actor_type, action, subject_id, subject_type,
            priority, created_at, updated_at, parent_id, NULL grandparent_id
          /* abilities-join-audited */
          FROM abilities ab
          WHERE ab.actor_id     IN (:actor_ids)
            AND ab.actor_type   = :actor_type
            AND ab.subject_type = :subject_type
            AND ab.subject_id   IN (:subject_ids)

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
          WHERE  grandparent.actor_id     IN (:actor_ids)
          AND    grandparent.actor_type   = :actor_type
          AND    parent.subject_type      = :subject_type
          AND    parent.subject_id        IN (:subject_ids)
        SQL

        select_most_capable_records(Ability.connection.select_all(sql).to_a).map do |record|
          Ability.send :instantiate, record
        end
      end

      # Authorization::Queries should be agnostic of participant implementation details.
      # We here break that rule because we need to invoke Repository.owning_organization_ids in order to derive
      # admin-on-owner abilities, that are no longer materialized, but clients still expect them.
      #
      # To derive abilities these abilities, this method does the following:
      # - compute user admin abilities over organizations
      # - forge abilities for each repo owned by those organizations
      def org_admin_abilities
        abilities = []
        subject_to_owner_map = subjects.map { |s| [s.id, s.owning_organization_id] }.to_h
        owning_organization_ids = subject_to_owner_map.values.compact

        if !owning_organization_ids.empty?
          org_admins_sql_bindings = {
            actor_ids: actor_ids,
            actor_type: actor_type,
            subject_type: "Organization",
            subject_ids: owning_organization_ids,
            direct: Ability.priorities[:direct],
            admin: Ability.actions[:admin],
          }
          org_admins_sql = Arel.sql <<-SQL, **org_admins_sql_bindings
          SELECT  id, actor_id, actor_type, action, subject_id, subject_type,
                  priority, created_at, updated_at, parent_id, NULL grandparent_id
            FROM  abilities ab
            WHERE ab.actor_id     IN (:actor_ids)
              AND ab.actor_type   =  :actor_type
              AND ab.subject_type =  :subject_type
              AND ab.subject_id   IN (:subject_ids)
              AND ab.action       =  :admin
          SQL
          org_admin_abilities = select_most_capable_records(Ability.connection.select_all(org_admins_sql).to_a).map do |record|
            Ability.send :instantiate, record
          end

          # We cannot use a map because this is a N-N relationship
          org_admin_to_org = org_admin_abilities.map { |ab| [ab.actor_id, ab.actor_type, ab.subject_id] }

          subject_to_owner_map.each do |subject_id, owner_id|
            org_admin_to_org
              .select { |_, _, subject_org_id| subject_org_id == owner_id }
              .each { |actorid, actortype, _| abilities << Ability.new(actor_id: actorid, actor_type: actortype, subject_id: subject_id, subject_type: subject_type, priority: Ability.priorities[:indirect], action: :admin) }
          end
        end
        abilities
      end

      private

      # Internal: Selects the most capable abilities between a set of actors
      # and a set of subjects. Selects one ability for each actor and subject
      # pair if one exists.
      #
      # abilities - [Hash of Ability attrs]
      #
      # Returns [Hash of Ability attrs]
      def select_most_capable_records(records)
        return records if records.empty?

        records.each_with_object({}) do |record, most_capables|
          key = [record["actor_id"], record["subject_id"]]

          if !most_capables.key?(key) || record["action"] > most_capables[key]["action"]
            most_capables[key] = record
          end
        end.values
      end

      def select_most_capable_abilities(abilities)
        return abilities if abilities.empty?

        abilities.each_with_object({}) do |ability, most_capables|
          key = [ability.actor_id, ability.subject_id]

          if !most_capables.key?(key) || Ability.actions[ability.action] > Ability.actions[most_capables[key].action]
            most_capables[key] = ability
          end
        end.values
      end

      def default_result
        []
      end

      def validation_errors
        errors = []

        if actor_type.nil?
          errors << validation_error(:missing_actor_type)
        end

        if subject_type.nil?
          errors << validation_error(:missing_subject_type)
        end

        errors
      end
    end
  end
end
