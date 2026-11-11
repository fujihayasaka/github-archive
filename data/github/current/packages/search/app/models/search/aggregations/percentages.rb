# typed: true
# frozen_string_literal: true

module Search
  module Aggregations
    class Percentages < Terms
      TermCount = Struct.new(:term, :count, :percentage, :language) do
        def platform_type_name
          "LanguageAggregate"
        end
      end

      def self.build(aggregation)
        aggregation.items.collect do |term|
          name, count = term.values_at("key", "doc_count")
          percentage = (count / aggregation.total.to_f * 100).round
          language = Linguist::Language[name || ""]
          TermCount.new(name, count, percentage, language)
        end
      end
    end
  end
end
