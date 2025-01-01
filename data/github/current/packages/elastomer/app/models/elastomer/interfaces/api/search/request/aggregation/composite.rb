# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          module Aggregation
            class Composite < T::Struct
              # This models the "nested" bucket aggregation in Elasticsearch. See here for more information:
              # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket-nested-aggregation.html

              include Bucketable

              class Order < T::Enum
                enums do
                  Asc = new("asc")
                  Desc = new("desc")
                end
              end

              class MissingBucketOrder < T::Enum
                enums do
                  First = new("first")
                  Last = new("last")
                end
              end

              class TermsSource < T::Struct
                const :slug, Symbol
                const :field, String
                const :order, T.nilable(Order)
                const :missing_bucket, T.nilable(T::Boolean)
                const :missing_order, T.nilable(MissingBucketOrder)

                sig { returns(T::Hash[Symbol, T.untyped]) }
                def to_hash
                  {
                    slug => {
                      terms: {
                        field:,
                        order: order&.serialize,
                        missing_bucket:,
                        missing_order: missing_order&.serialize,
                      }.compact
                    }
                  }
                end
              end

              # Required
              const :slug, Symbol
              const :sources, T::Array[TermsSource]

              # Optional
              const :size, T.nilable(Integer)
              const :after, T.nilable(T::Hash[T.any(Symbol, String), T.untyped])
              const :meta, T.nilable(T::Hash[T.untyped, T.untyped])
              const :aggs, Aggregation::Collection, factory: -> { Aggregation::Collection.new }

              sig { override.returns(Symbol) }
              def aggregation_type_key
                :composite
              end

              sig { override.returns(T::Hash[Symbol, T.untyped]) }
              def body
                { sources: sources.map(&:to_hash), size:, after:, meta: }.compact
              end
            end
          end
        end
      end
    end
  end
end
