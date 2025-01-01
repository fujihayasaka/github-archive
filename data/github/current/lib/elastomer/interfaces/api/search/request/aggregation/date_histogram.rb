# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          module Aggregation
            class DateHistogram < T::Struct
              # This models the "date histogram" bucket aggregation in Elasticsearch. See here for more information:
              # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket-datehistogram-aggregation.html

              include Bucketable

              # Required
              const :slug, Symbol
              const :field, String

              # Optional
              const :calendar_interval, T.nilable(String)
              const :fixed_interval, T.nilable(String)
              const :format, T.nilable(String)
              # hard_bounds optionally specifies the min and max Date bounds for the histogram
              const :hard_bounds, T.nilable(T::Hash[T.untyped, T.untyped])
              const :meta, T.nilable(T::Hash[T.untyped, T.untyped])
              const :aggs, Aggregation::Collection, factory: -> { Aggregation::Collection.new }

              sig { override.returns(Symbol) }
              def aggregation_type_key
                :date_histogram
              end

              sig { override.returns(T::Hash[Symbol, T.untyped]) }
              def body
                {
                  field:,
                  calendar_interval:,
                  fixed_interval:,
                  format:,
                  hard_bounds:,
                }.compact
              end
            end
          end
        end
      end
    end
  end
end
