# typed: true
# frozen_string_literal: true

module Search
  module Aggregations
    class Aggregation
      include Enumerable

      attr_reader :items

      def each(&block)
        items.each(&block)
      end

      def as_json(options = {})
        items
      end
    end
  end
end
