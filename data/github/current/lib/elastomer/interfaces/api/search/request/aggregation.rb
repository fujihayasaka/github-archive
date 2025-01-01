# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          module Aggregation
            autoload :Aggregatable, "elastomer/interfaces/api/search/request/aggregation/aggregatable"
            autoload :Bucketable, "elastomer/interfaces/api/search/request/aggregation/bucketable"
            autoload :Metricable, "elastomer/interfaces/api/search/request/aggregation/metricable"
            autoload :Collection, "elastomer/interfaces/api/search/request/aggregation/collection"

            autoload :Avg, "elastomer/interfaces/api/search/request/aggregation/avg"
            autoload :Composite, "elastomer/interfaces/api/search/request/aggregation/composite"
            autoload :CumulativeSum, "elastomer/interfaces/api/search/request/aggregation/cumulative_sum"
            autoload :DateHistogram, "elastomer/interfaces/api/search/request/aggregation/date_histogram"
            autoload :Filter, "elastomer/interfaces/api/search/request/aggregation/filter"
            autoload :Global, "elastomer/interfaces/api/search/request/aggregation/global"
            autoload :Max, "elastomer/interfaces/api/search/request/aggregation/max"
            autoload :Min, "elastomer/interfaces/api/search/request/aggregation/min"
            autoload :Nested, "elastomer/interfaces/api/search/request/aggregation/nested"
            autoload :ReverseNested, "elastomer/interfaces/api/search/request/aggregation/reverse_nested"
            autoload :Sum, "elastomer/interfaces/api/search/request/aggregation/sum"
            autoload :Terms, "elastomer/interfaces/api/search/request/aggregation/terms"
            autoload :TopHits, "elastomer/interfaces/api/search/request/aggregation/top_hits"
          end
        end
      end
    end
  end
end
