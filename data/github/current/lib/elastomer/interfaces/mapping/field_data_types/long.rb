# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Mapping
      module FieldDataTypes
        # The mapping type for a long field.
        #
        # See: https://www.elastic.co/guide/en/elasticsearch/reference/current/number.html
        class Long
          extend T::Sig
          include FieldDataType

          sig { override.returns(FieldDataTypeName) }
          def name
            FieldDataTypeName::Long
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
