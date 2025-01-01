# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Mapping
      module FieldDataTypes
        # The mapping for a common type of multi-field.
        #
        # See: https://www.elastic.co/guide/en/elasticsearch/reference/current/multi-fields.html
        class KeywordMultiField < T::Struct
          include FieldDataType

          prop :analyzer, T.nilable(Analyzer)
          prop :search_analyzer, T.nilable(Analyzer)
          prop :fields, T.nilable(T::Hash[Symbol, FieldDataType]), factory: ->() { { keyword: FieldDataTypes::Keyword.new } }
          prop :copy_to, T.nilable(T.any(String, T::Array[String]))

          sig { override.returns(FieldDataTypeName) }
          def name
            FieldDataTypeName::Text
          end

          sig { override.returns(T::Hash[T.untyped, T.untyped]) }
          def to_hash
            {
              type: name.serialize,
              analyzer: analyzer&.serialize,
              search_analyzer: search_analyzer&.serialize,
              fields: fields&.each_with_object({}) { |(name, config), result| result[name] = config.to_hash },
              copy_to: Array(copy_to).presence,
            }.compact
          end
        end
      end
    end
  end
end
