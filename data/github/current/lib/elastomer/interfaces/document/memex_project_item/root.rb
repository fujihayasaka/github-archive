# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Document
      module MemexProjectItem
        class Root < T::Struct
          include GitHub::Memoizer

          # This is a configuration option; it does not appear in the serialized document (the result of `to_hash`)
          prop :cluster_on_8_plus, T::Boolean, default: false

          const :_id, String
          const :_routing, T.nilable(Integer)
          const :_type, T.nilable(String)
          const :_blob, T.nilable(T::Hash[T.untyped, T.untyped])
          const :content, MemexProjectItem::Content
          const :field_values, T::Array[MemexProjectItem::FieldValue]
          const :metadata, Metadata

          sig { returns(T::Hash[T.untyped, T.untyped]) }
          memoize def to_hash
            result = {
              _id: _id,
              _blob: _blob,
              content: content.to_hash,
              field_values: field_values.map(&:to_hash),
              **metadata.to_hash
            }

            # ES8-COMPATIBILITY: Omit _type and _routing keys when necessary (they are required on ES 5 but no longer
            # accepted within the document on ES 8)
            result[:_type] = _type if _type.present? && !cluster_on_8_plus
            result[:_routing] = _routing if _routing.present? && !cluster_on_8_plus

            result
          end
        end
      end
    end
  end
end
