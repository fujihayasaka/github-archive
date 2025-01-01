# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          autoload :Aggregation, "elastomer/interfaces/api/search/request/aggregation"
          autoload :Body, "elastomer/interfaces/api/search/request/body"
          autoload :Params, "elastomer/interfaces/api/search/request/params"

          autoload :RangeQuery, "elastomer/interfaces/api/search/request/range_query"
          autoload :TermQuery, "elastomer/interfaces/api/search/request/term_query"
          autoload :WildcardQuery, "elastomer/interfaces/api/search/request/wildcard_query"

          autoload :Field, "elastomer/interfaces/api/search/request/field"
          autoload :IndicesBoost, "elastomer/interfaces/api/search/request/indices_boost"
          autoload :Knn, "elastomer/interfaces/api/search/request/knn"
          autoload :Pit, "elastomer/interfaces/api/search/request/pit"
          autoload :RuntimeMappings, "elastomer/interfaces/api/search/request/runtime_mappings"
          autoload :Source, "elastomer/interfaces/api/search/request/source"
        end
      end
    end
  end
end
