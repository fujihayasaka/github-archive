# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Mapping
      module FieldDataTypes
        # The mapping type for an integer field.
        #
        # See: https://www.elastic.co/guide/en/elasticsearch/reference/current/number.html
        class Integer < T::Struct
          include FieldDataType

          prop :copy_to, T.nilable(T.any(String, T::Array[String]))

          sig { override.returns(FieldDataTypeName) }
          def name
            FieldDataTypeName::Integer
          end

          sig { override.returns(T::Hash[T.untyped, T.untyped]) }
          def to_hash
            {
              type: name.serialize,
              copy_to: Array(copy_to).presence,
            }.compact
          end
        end
      end
    end
  end
end
