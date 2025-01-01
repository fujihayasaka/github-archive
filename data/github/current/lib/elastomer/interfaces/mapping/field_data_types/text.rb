# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Mapping
      module FieldDataTypes
        # The mapping type for a text field.
        #
        # See: https://www.elastic.co/guide/en/elasticsearch/reference/current/text.html#text-field-type.
        class Text < T::Struct
          extend T::Sig
          include FieldDataType

          prop :analyzer, T.nilable(Analyzer)
          prop :search_analyzer, T.nilable(Analyzer)

          sig { override.returns(FieldDataTypeName) }
          def name
            FieldDataTypeName::Text
          end

          sig { override.returns(T::Hash[T.untyped, T.untyped]) }
          def to_hash
            {
              type: name.serialize,
              analyzer: analyzer&.serialize,
              search_analyzer: search_analyzer&.serialize
            }.compact
          end
        end
      end
    end
  end
end
