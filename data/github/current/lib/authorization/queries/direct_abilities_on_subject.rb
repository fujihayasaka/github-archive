# typed: true
# frozen_string_literal: true

require_relative "base_query"

module Authorization
  module Queries
    class DirectAbilitiesOnSubject < BaseQuery

      attr_reader :actor_type, :subject, :action

      def initialize(subject:, actor_type: :any, action:)
        @subject = subject
        @actor_type = actor_type
        @action = action
      end

      def execute_implementation
        return default_result unless subject.participates?
        ActiveRecord::Base.connected_to(role: :reading) do
          bindings = {
            direct: Ability.priorities[:direct],
            subject_id: subject.ability_id,
            subject_type: subject.ability_type,
          }
          sql = Arel.sql(<<-SQL, **bindings)
            SELECT ab.*
            FROM abilities ab
            WHERE ab.priority = :direct
              AND ab.subject_id = :subject_id
              AND ab.subject_type = :subject_type
          SQL

          if actor_type && actor_type != :any
            sql += Arel.sql(<<-SQL, actor_type: actor_type)
              AND ab.actor_type = :actor_type
            SQL
          end

          if action != :any
            sql += Arel.sql(<<-SQL, action: Ability.actions[action.to_sym])
             AND ab.action = :action
            SQL
          end

          Ability.find_by_sql(sql)
        end
      end

      def default_result
        []
      end

      def validation_errors
        errors = []

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
