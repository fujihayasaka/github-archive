# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          module Aggregation

            # This models the "cumulative sum" pipeline aggregation in Elasticsearch. See here for more information:
            # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-pipeline-cumulative-sum-aggregation.html
            class CumulativeSum < T::Struct
              include Metricable

              # Required
              const :slug, Symbol
              const :buckets_path, String

              # Optional
              const :format, T.nilable(String)
              const :meta, T.nilable(T::Hash[T.untyped, T.untyped])

              sig { override.returns(Symbol) }
              def aggregation_type_key
                :cumulative_sum
              end

              sig { override.returns(T::Hash[Symbol, T.untyped]) }
              def body
                {
                  buckets_path:,
                  format:,
                }.compact
              end
            end
          end
        end
      end
    end
  end
end
