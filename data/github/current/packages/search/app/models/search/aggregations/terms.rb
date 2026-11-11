# typed: true
# frozen_string_literal: true

module Search
  module Aggregations
    class Terms < Aggregation
      attr_reader :total
      attr_reader :other

      def initialize(aggregation)
        @items = aggregation["buckets"]
        @other = aggregation["sum_other_doc_count"]
        @total = @items.map { |item| item["doc_count"] }.sum + @other
      end

      def terms
        items
      end

      def as_json(options = {})
        export = {}
        @items.each do |term|
          export[term["key"]] = term["doc_count"]
        end
        export
      end

      def ==(obj)
        obj.items == items && obj.total == total &&
          obj.other == other
      end
    end
  end
end
