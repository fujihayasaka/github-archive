# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          module Aggregation
            class ReverseNested < T::Struct
              # A special single bucket aggregation that enables aggregating on parent docs from nested documents.
              # Effectively this aggregation can break out of the nested block structure and link to other nested
              # structures (via `path`) or the root document, which allows nesting other aggregations that aren’t
              # part of the nested object in a nested aggregation.
              #
              # Note: The reverse_nested aggregation must be defined inside a nested aggregation.
              #
              # See https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket-reverse-nested-aggregation.html
              # for more information.
              extend T::Sig
              include Bucketable

              # Required
              const :slug, Symbol

              # Optional
              const :path, T.nilable(String)
              const :meta, T.nilable(T::Hash[T.untyped, T.untyped])
              const :aggs, Aggregation::Collection, factory: -> { Aggregation::Collection.new }

              sig { override.returns(Symbol) }
              def aggregation_type_key
                :reverse_nested
              end

              sig { override.returns(T::Hash[Symbol, T.untyped]) }
              def body
                { path: }.compact
              end
            end
          end
        end
      end
    end
  end
end
