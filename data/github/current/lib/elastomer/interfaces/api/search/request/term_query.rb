# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          # This models Elasticsearch "Term Query" shapes. See the following documentation for more info:
          # https://www.elastic.co/guide/en/elasticsearch/reference/8.14/query-dsl-term-query.html
          class TermQuery < T::Struct
            extend T::Sig

            # Required
            const :field_path, String
            const :value, String

            # Optional
            const :boost, T.nilable(Float), default: nil
            const :case_insensitive, T.nilable(T::Boolean), default: false

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                term: {
                  field_path => {
                    value:,
                    case_insensitive:,
                    boost:,
                  }.compact
                }
              }
            end
          end
        end
      end
    end
  end
end
