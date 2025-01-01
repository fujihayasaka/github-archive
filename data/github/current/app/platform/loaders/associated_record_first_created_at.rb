# typed: true
# frozen_string_literal: true

module Platform
  module Loaders

    # Returns the first created_at of an associated record type.
    # Note: Useful for identifying spammers (especially in relation to when the
    # account was created).
    class AssociatedRecordFirstCreatedAt < Platform::Loader
      def self.load(model, association)
        reflection = model.class.reflections[association.to_s]

        if reflection.nil?
          raise Errors::Internal.new("#{association} association does not exist on #{model.class}")
        end

        self.for(reflection).load(model.id)
      end

      def initialize(reflection)
        @reflection = reflection
      end

      def fetch(model_ids)
        rows = @reflection.klass.connection.select_rows(Arel.sql(<<-SQL, model_ids: model_ids))
          SELECT
            stats.foreign_key,
            first_#{@reflection.table_name}.created_at AS first_created_at
          FROM (
            SELECT
              #{@reflection.foreign_key} AS foreign_key,
              MIN(id) AS first_id
            FROM #{@reflection.table_name}
            WHERE #{@reflection.foreign_key} IN (:model_ids)
            GROUP BY #{@reflection.foreign_key}
          ) stats
          JOIN #{@reflection.table_name} first_#{@reflection.table_name} ON first_#{@reflection.table_name}.id = stats.first_id
        SQL

        model_ids.inject(Hash.new) do |result, model_id|
          _, first_created_at = rows.find { |row| row[0] == model_id }

          result[model_id] = first_created_at
          result
        end
      end
    end
  end
end
