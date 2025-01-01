# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          module Aggregation
            module Aggregatable
              # This interface must be included in any class that is to be used as an aggregation in a search request.
              # It provides the minimum common interface that all aggregations must implement, as well as defaults for
              # any optional parameters that are common to all aggregations.
              #
              # See https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations.html for more info.

              extend T::Helpers
              interface!

              sig { abstract.returns(Symbol) }
              def aggregation_type_key; end

              # The slug is a unique identifier for the aggregation, used to match the aggregation in the response to the
              # aggregation in the request. When serialized to a hash, the slug is used as the hash key -- for example, if
              # the slug is `:my_aggregation`, the serialized version will be:
              #
              # aggs: {
              #   my_aggregation: {...}
              # }
              #
              # Note that it is the responsibility of the to_hash method below to serialize the aggregation this way.
              sig { abstract.returns(T.any(Symbol, Integer)) }
              def slug; end

              # This is the main logic of the aggregation (as opposed to, for example, metadata or sub-aggregations),
              # which will be specific to the aggregation type. Note that, at time of writing, it is expected that
              # Aggregatable implementations will specify the body as part of the class definition, rather than users
              # providing it at runtime.
              sig { abstract.returns(T::Hash[T.untyped, T.untyped]) }
              def body; end

              # The meta method returns a hash of additional metadata that can be optionally included in the aggregation.
              # See https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations.html#add-metadata-to-an-agg
              sig { abstract.returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
              def meta; end

              # The to_hash method serializes the aggregation to a hash that can be included in the search request. The
              # hash should be structured as follows:
              #
              # {
              #  slug => {...} # the contents of the hash here are specific to the aggregation type
              # }
              sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
              def to_hash; end
            end
          end
        end
      end
    end
  end
end
