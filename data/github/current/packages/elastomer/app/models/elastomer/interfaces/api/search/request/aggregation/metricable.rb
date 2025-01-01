# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          module Aggregation
            module Metricable
              # An interface for Elasticsearch's metrics aggregations. The aggregations in this family compute metrics
              # based on values extracted in one way or another from the documents that are being aggregated. The values
              # are typically extracted from the fields of the document (using the field data), but can also be generated
              # using scripts.
              #
              # Note that, unlike Bucket aggregations, metrics aggregations can't include sub-aggregations.
              #
              # See https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-metrics.html for
              # more info.

              extend T::Helpers
              include Aggregatable
              abstract!

              sig { override.returns(T::Hash[Symbol, T.untyped]) }
              def to_hash
                {
                  slug => {
                    aggregation_type_key => body.compact,
                    :meta => meta,
                  }.compact
                }
              end
            end
          end
        end
      end
    end
  end
end
