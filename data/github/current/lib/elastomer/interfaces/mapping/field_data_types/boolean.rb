# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Mapping
      module FieldDataTypes
        # The mapping type for a boolean field.
        #
        # See: https://www.elastic.co/guide/en/elasticsearch/reference/current/boolean.html
        class Boolean < T::Struct
          include FieldDataType

          sig { override.returns(FieldDataTypeName) }
          def name
            FieldDataTypeName::Boolean
          end

          sig { override.returns(T::Hash[T.untyped, T.untyped]) }
          def to_hash
            {
              type: name.serialize
            }
          end
        end
      end
    end
  end
end
