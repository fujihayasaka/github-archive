# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Response
        class Hit < T::Struct
          extend T::Sig

          const :_index, String
          const :_id, String
          const :_score, T.nilable(Float)
          const :_source, T::Hash[T.untyped, T.untyped]
          const :fields, T.nilable(T::Array[String])
          const :sort, T.nilable(T::Array[T.untyped])

          sig { returns(T::Hash[Symbol, T.untyped]) }
          def to_hash
            {
              _index: _index,
              _id: _id,
              _score: _score,
              _source: _source,
              fields:,
              sort:,
            }
          end

          sig { params(response: T::Hash[String, T.untyped]).returns(Hit) }
          def self.from_es_response(response)
            new(
              _index: response["_index"],
              _id: response["_id"],
              _score: response["_score"],
              _source: response["_source"],
              fields: response["fields"],
              sort: response["sort"],
            )
          end
        end

      end
    end
  end
end
