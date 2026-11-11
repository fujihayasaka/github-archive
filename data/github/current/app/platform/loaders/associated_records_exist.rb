# typed: true
# frozen_string_literal: true

module Platform
  module Loaders

    # Check whether any records exist for an association.
    class AssociatedRecordsExist < Platform::Loader
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
        counts = @reflection.klass.connection.select_rows(Arel.sql(<<-SQL, model_ids: model_ids)).to_h { |row| [row[0], row[2]] }
          SELECT
            #{@reflection.foreign_key},
            user_id,
            count(id)
          FROM #{@reflection.table_name}
          WHERE #{@reflection.foreign_key} IN (:model_ids)
          GROUP BY user_id
        SQL

        model_ids.inject(Hash.new) do |result, model_id|
          result[model_id] = counts[model_id].present?
          result
        end
      end
    end
  end
end
