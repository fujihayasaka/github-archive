# typed: true
# frozen_string_literal: true

module Releases
  module Loaders
    class SlottedCounter < Platform::Loader
      def self.load(record_type, record_id)
        self.for(record_type).load(record_id)
      end

      def initialize(record_type)
        @record_type = record_type
      end

      private

      attr_reader :record_type

      def fetch(record_ids)
        statement = <<~SQL
          SELECT record_id, SUM(`count`)
          FROM slotted_counters
          WHERE record_type = :record_type AND record_id IN (:record_ids)
          GROUP BY record_id
        SQL
        binds = {
          record_type: record_type,
          record_ids: record_ids,
        }
        results = ApplicationRecord::Ballast.connection.select_rows(Arel.sql(statement, **binds))
        result_hash = Hash[results]

        count_hash = {}
        record_ids.each { |id| count_hash[id] = result_hash[id]&.to_i || 0 }

        count_hash
      end
    end
  end
end
