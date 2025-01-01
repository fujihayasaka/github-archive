# typed: true
# frozen_string_literal: true

module Search
  module Aggregations
    class DateHistogram < Aggregation
      def initialize(aggregation)
        @items = aggregation["buckets"]
      end

      def entries
        items
      end

      def ==(obj)
        obj.items == items
      end
    end
  end
end
