# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          module Aggregation

            # This models the "max" (maximum) metric aggregation in Elasticsearch. See here for more information:
            # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-metrics-max-aggregation.html
            class Max < T::Struct
              include Metricable

              # Required
              const :slug, Symbol
              const :field, String

              # Optional
              const :meta, T.nilable(T::Hash[T.untyped, T.untyped])

              sig { override.returns(Symbol) }
              def aggregation_type_key
                :max
              end

              sig { override.returns(T::Hash[Symbol, T.untyped]) }
              def body
                { field: }
              end
            end
          end
        end
      end
    end
  end
end
