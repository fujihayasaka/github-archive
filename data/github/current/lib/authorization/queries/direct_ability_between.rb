# typed: true
# frozen_string_literal: true

require_relative "base_query"

module Authorization
  module Queries
    class DirectAbilityBetween < BaseQuery

      attr_reader :actor, :subject, :action

      def initialize(actor:, subject:, action:)
        @actor = actor
        @subject = subject
        @action = action
      end

      def execute_implementation
        return default_result unless subject.participates? && actor.participates?

        options = {
          actor_id:     actor.ability_id,
          actor_type:   actor.ability_type,
          subject_id:   subject.ability_id,
          subject_type: subject.ability_type,
        }

        sql = Arel.sql(<<-SQL, **options)
          SELECT *
          FROM abilities
          WHERE priority = 1
            AND actor_id = :actor_id
            AND actor_type = :actor_type
            AND subject_id = :subject_id
            AND subject_type = :subject_type
        SQL

        if action != :any
          sql += Arel.sql(<<-SQL, action: Ability.actions[action])
            AND action = :action
          SQL
        end

        sql += Arel.sql <<-SQL
          LIMIT 1
        SQL

        Ability.find_by_sql(sql).first
      end

      def validation_errors
        errors = []

        unless valid_actor?(actor)
          errors << validation_error(:invalid_actor, actor: actor)
        end

        unless valid_subject?(subject)
          errors << validation_error(:invalid_subject, subject: subject)
        end

        if action != :any && !valid_action?(action)
          errors << validation_error(:invalid_action, action: action)
        end

        errors
      end
    end
  end
end
