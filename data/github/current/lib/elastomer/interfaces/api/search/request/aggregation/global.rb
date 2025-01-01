# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          module Aggregation
            class Global < T::Struct
              # Note that, unlike some other aggregation types, `global` requires a sub-aggregation. This is because
              # the `global` aggregation is a parent aggregation that has no buckets of its own. It simply applies the
              # sub-aggregation to the entire search result.
              #
              # This also means that `global` aggregations can only be included at the top level of an aggregation
              # collection. They cannot be nested within other aggregations.
              #
              # See https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket-global-aggregation.html
              # for more information.
              extend T::Sig
              include Bucketable

              # Required
              const :slug, Symbol
              const :aggs, Aggregation::Collection, factory: -> { Aggregation::Collection.new }

              # Optional
              const :meta, T.nilable(T::Hash[T.untyped, T.untyped])

              sig { override.returns(Symbol) }
              def aggregation_type_key
                :global
              end

              # Global aggregations have no body per se -- `global: {}` is effectively just a keyword indicating that
              # the sub-aggregation should be applied to the entire search result.
              sig { override.returns(T::Hash[Symbol, T.untyped]) }
              def body
                {}
              end
            end
          end
        end
      end
    end
  end
end
