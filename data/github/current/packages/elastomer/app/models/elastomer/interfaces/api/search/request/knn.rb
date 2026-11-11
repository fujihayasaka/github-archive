# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          class Knn < T::Struct
            # This is modeled after field references in the Elasticsearch Search API documentation:
            #
            # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-search.html

            const :field, String
            const :filter, T.nilable(T::Hash[T.untyped, T.untyped])
            const :k, Integer
            const :num_candidates, Integer
            const :query_vector, T.nilable(T::Array[Float])
            const :query_vector_builder, T.nilable(T::Hash[T.untyped, T.untyped])
            const :similarity, T.nilable(Float)

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                field:,
                filter:,
                k:,
                num_candidates:,
                query_vector:,
                query_vector_builder:,
                similarity:,
              }.compact
            end
          end
        end
      end
    end
  end
end
