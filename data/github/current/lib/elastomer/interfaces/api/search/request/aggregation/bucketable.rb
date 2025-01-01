# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          module Aggregation
            module Bucketable
              # An interface for Elasticsearch's bucket aggregations. Bucket aggregations are aggregations that group
              # documents into buckets based on some criteria. In terms of data structure, they differ from metric
              # aggregations in that they can contain sub-aggregations.
              #
              # See https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket.html for
              # more info.
              extend T::Sig
              extend T::Helpers
              include Aggregatable
              abstract!

              sig { abstract.returns(Aggregation::Collection) }
              def aggs; end

              sig { overridable.params(aggregation: Aggregatable).returns(T.self_type) }
              def add_subaggregation(aggregation)
                aggs.push(aggregation)
                self
              end

              sig { override.returns(T::Hash[Symbol, T.untyped]) }
              def to_hash
                {
                  slug => {
                    aggregation_type_key => body.compact,
                    :aggs => aggs.to_hash,
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
