# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  class StatsResult

    sig { returns(T::Array[T::Hash[String, T.untyped]]) }
    attr_reader :records

    sig { returns(Integer) }
    attr_reader :total_record_count

    sig { params(dataset: Kusto::Data::Dataset).void }
    def initialize(dataset)
      @dataset = dataset
      @records = T.let(to_records(dataset), T::Array[T::Hash[String, T.untyped]])
      @total_record_count = T.let(@dataset.primary_result_tables.size > 1 ? @dataset.primary_result_tables[1]&.rows&.first&.first : @records.size, Integer)
    end

    private

    sig { params(dataset: Kusto::Data::Dataset).returns(T::Array[T::Hash[String, T.untyped]]) }
    def to_records(dataset)
      dataset.primary_result_table.rows.map do |row|
        dataset.primary_result_table.columns.each_with_index.each_with_object({}) do |(column, i), hash|
          hash[column.name] = row[i] unless row[i].nil?
        end
      end
    end
  end
end
