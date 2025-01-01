# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          # This models Elasticsearch "Semantic" shapes. See the following documentation for more info:
          # https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-semantic-query.html
          class Semantic < T::Struct
            # Required
            const :field, String
            const :query, String

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                field:,
                query:,
              }
            end
          end
        end
      end
    end
  end
end
