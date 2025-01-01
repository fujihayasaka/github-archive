# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          module Aggregation
            class Nested < T::Struct
              # This models the "nested" bucket aggregation in Elasticsearch. See here for more information:
              # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket-nested-aggregation.html
              extend T::Sig
              include Bucketable

              # Required
              const :slug, T.any(Symbol, Integer)
              const :path, String

              # Optional
              const :meta, T.nilable(T::Hash[T.untyped, T.untyped])
              const :aggs, Aggregation::Collection, factory: -> { Aggregation::Collection.new }

              sig { override.returns(Symbol) }
              def aggregation_type_key
                :nested
              end

              sig { override.returns(T::Hash[Symbol, T.untyped]) }
              def body
                { path: }
              end
            end
          end
        end
      end
    end
  end
end
