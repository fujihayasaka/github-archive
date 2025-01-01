# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Response
        class Total < T::Struct
          class Relation < T::Enum
            enums do
              Eq = new("eq")
              Gte = new("gte")
            end
          end

          const :value, Integer
          const :relation, Relation

          sig { returns(T::Hash[Symbol, T.untyped]) }
          def to_hash
            {
              value:,
              relation: relation.serialize,
            }
          end

          sig { params(response: T::Hash[String, T.untyped]).returns(Total) }
          def self.from_es_response(response)
            new(
              value: response["value"],
              relation: Relation.deserialize(response["relation"]),
            )
          end
        end
      end
    end
  end
end
