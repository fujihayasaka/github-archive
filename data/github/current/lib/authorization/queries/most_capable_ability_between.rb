# typed: true
# frozen_string_literal: true

require_relative "base_query"

module Authorization
  module Queries
    class MostCapableAbilityBetween < BaseQuery
      include Scientist

      attr_reader :actor, :subject

      def initialize(actor:, subject:)
        @actor = actor
        @subject = subject
      end

      def execute_implementation
        return default_result unless subject.participates? && actor.participates?

        PermissionCache.fetch permission_cache_key do
          router = Permissions::QueryRouter.for(subject_types: [subject.ability_type])
          model = router.model
          bindings = {
            actor_id:     actor.ability_id,
            actor_type:   actor.ability_type,
            subject_type: subject.ability_type,
            subject_id:   subject.ability_id,
            direct:       Ability.priorities[:direct],
            indirect:     Ability.priorities[:indirect],
            abilities_or_permissions: Arel.sql(model.table_name)
          }
          sql = build_query(bindings,
            owner_id: subject.owning_organization_id,
            owner_type: subject.owning_organization_type,
            fine_grained: router.fine_grained?(subject.ability_type),
          )

          model.find_by_sql(sql).first
        end
      end

      def validation_errors
        errors = []

        unless valid_actor?(actor)
          errors << validation_error(:invalid_actor, actor: actor)
        end

        unless valid_subject?(subject)
          errors << validation_error(:invalid_subject, subject: subject)
        end

        errors
      end

      private

      def build_query(bindings, owner_id:, owner_type:, fine_grained:)
        bindings[:admin] = Ability.actions[:admin]

        sql = Arel.sql(<<-SQL, **bindings)
          SELECT id,
              actor_id, actor_type, action, subject_id, subject_type,
              priority, created_at, updated_at, parent_id, NULL grandparent_id
          FROM   :abilities_or_permissions
          WHERE  actor_id     = :actor_id
          AND    actor_type   = :actor_type
          AND    subject_id   = :subject_id
          AND    subject_type = :subject_type
          AND    priority    <= :direct
        SQL

        if owner_id.present? && owner_type.present?
          bindings[:owner_id] = owner_id
          bindings[:owner_type] = owner_type
          sql += Arel.sql(<<-SQL, **bindings)

            UNION

            SELECT id,
              actor_id, actor_type,
              action,
              :subject_id as subject_id,
              :subject_type as subject_type,
              :indirect as priority,
              created_at, updated_at,
              id as parent_id,
              NULL grandparent_id
            FROM   :abilities_or_permissions
            WHERE  actor_id     = :actor_id
            AND    actor_type   = :actor_type
            AND    subject_id   = :owner_id
            AND    subject_type = :owner_type
            AND    priority     = :direct
            AND    action       = :admin
          SQL
        end

        if !fine_grained
          sql += Arel.sql(<<-SQL, **bindings)
            UNION

            SELECT NULL AS id,
              /* abilities-join-audited */
              grandparent.actor_id, grandparent.actor_type,
              parent.action,
              parent.subject_id, parent.subject_type,
              :indirect AS priority, NULL AS created_at, NULL AS updated_at,
              parent.id AS parent_id, grandparent.id AS grandparent_id
            FROM   abilities parent
            JOIN   abilities grandparent
            ON     grandparent.subject_type = parent.actor_type
            AND    grandparent.subject_id   = parent.actor_id
            AND    parent.priority          <= :direct
            AND    grandparent.priority     <= :direct
            WHERE  grandparent.actor_id     = :actor_id
            AND    grandparent.actor_type   = :actor_type
            AND    parent.subject_id        = :subject_id
            AND    parent.subject_type      = :subject_type
          SQL
        end

        sql += Arel.sql <<-SQL
          ORDER BY action DESC, priority DESC
          LIMIT  1
        SQL

        sql
      end

      MCAB_CACHE_PREFIX = "most_capable_ability_between"
      def permission_cache_key
        [MCAB_CACHE_PREFIX, @actor.ability_type, @actor.ability_id, @subject.ability_type, @subject.ability_id]
      end
    end
  end
end
