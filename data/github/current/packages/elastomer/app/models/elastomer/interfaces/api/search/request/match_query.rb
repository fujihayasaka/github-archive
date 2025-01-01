# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          # This models Elasticsearch "Match Query" shapes. See the following documentation for more info:
          # https://www.elastic.co/docs/reference/query-languages/query-dsl/query-dsl-match-query
          class MatchQuery < T::Struct
            # Required
            const :field_path, String
            const :value, String

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                match: {
                  field_path.to_sym => value
                }
              }
            end
          end
        end
      end
    end
  end
end
