# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          # This models Elasticsearch "Range Query" shapes. See the following documentation for more info:
          # https://www.elastic.co/guide/en/elasticsearch/reference/8.14/query-dsl-range-query.html
          class RangeQuery < T::Struct
            extend T::Sig

            # This nested class models the core comparison operators used in Elasticsearch range queries. See here:
            # https://www.elastic.co/guide/en/elasticsearch/reference/8.14/query-dsl-range-query.html#range-query-field-params
            #
            # Note that this is independent of `RangeQuery` itself so that child methods can construct these operators
            # for composing into higher-level `RangeQuery` constructions where more context about the overall query is known.
            class Operators < T::Struct
              extend T::Sig

              # At least one of the below is required
              const :gt, T.nilable(T.any(String, Integer, Float))
              const :gte, T.nilable(T.any(String, Integer, Float))
              const :lte, T.nilable(T.any(String, Integer, Float))
              const :lt, T.nilable(T.any(String, Integer, Float))

              sig { params(hash: T::Hash[Symbol, T.untyped]).returns(Operators) }
              def self.from_hash(hash)
                if [:gt, :gte, :lt, :lte].all? { hash[_1].nil? }
                  raise ArgumentError, "At least one of gt, gte, lt, lte must be present"
                end
                new(
                  gte: hash[:gte],
                  lte: hash[:lte],
                  gt: hash[:gt],
                  lt: hash[:lt],
                )
              end

              sig { returns(T::Hash[Symbol, T.untyped]) }
              def to_hash
                { gt:, gte:, lt:, lte: }.compact
              end
            end

            # Required
            const :field_path, String
            # The range comparison operators, e.g. { gt:, gte:, lt:, lte: }
            const :operators, Operators

            # Optional
            const :boost, T.nilable(Float)
            const :format, T.nilable(String)
            const :relation, T.nilable(String)
            const :time_zone, T.nilable(String)

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                range: {
                  field_path.to_sym => {
                    boost:,
                    format:,
                    relation:,
                    time_zone:
                  }.merge(operators.to_hash).compact
                }
              }
            end
          end
        end
      end
    end
  end
end
