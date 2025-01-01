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

            autoload :Composite, "elastomer/interfaces/api/search/request/aggregation/composite"
            autoload :Filter, "elastomer/interfaces/api/search/request/aggregation/filter"
            autoload :Global, "elastomer/interfaces/api/search/request/aggregation/global"
            autoload :Nested, "elastomer/interfaces/api/search/request/aggregation/nested"
            autoload :ReverseNested, "elastomer/interfaces/api/search/request/aggregation/reverse_nested"
            autoload :Terms, "elastomer/interfaces/api/search/request/aggregation/terms"
            autoload :TopHits, "elastomer/interfaces/api/search/request/aggregation/top_hits"
          end
        end
      end
    end
  end
end
