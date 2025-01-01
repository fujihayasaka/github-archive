# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          module Aggregation
            class Filter < T::Struct
              extend T::Sig
              include Bucketable

              # Required
              const :slug, Symbol
              const :filter, T::Hash[T.untyped, T.untyped]

              # Optional
              const :meta, T.nilable(T::Hash[T.untyped, T.untyped])
              const :aggs, Aggregation::Collection, factory: -> { Aggregation::Collection.new }

              sig { override.returns(Symbol) }
              def aggregation_type_key
                :filter
              end

              sig { override.returns(T::Hash[Symbol, T.untyped]) }
              def body
                filter
              end
            end
          end
        end
      end
    end
  end
end
