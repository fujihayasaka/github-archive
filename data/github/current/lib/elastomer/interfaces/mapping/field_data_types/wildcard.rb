# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Mapping
      module FieldDataTypes
        # The mapping type for a specialized wildcard keyword.
        #
        # See: https://www.elastic.co/guide/en/elasticsearch/reference/current/keyword.html#wildcard-field-type
        class Wildcard < T::Struct
          include FieldDataType

          sig { override.returns(FieldDataTypeName) }
          def name
            FieldDataTypeName::Wildcard
          end

          sig { override.returns(T::Hash[T.untyped, T.untyped]) }
          def to_hash
            {
              type: name.serialize,
            }
          end
        end
      end
    end
  end
end
