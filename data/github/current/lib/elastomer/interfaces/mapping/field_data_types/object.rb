# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Mapping
      module FieldDataTypes
        # The mapping type for an object field.
        #
        # See: https://www.elastic.co/guide/en/elasticsearch/reference/current/object.html
        class Object < T::Struct
          include FieldDataType

          # Require explicit field mapping by default so that document sizes don't unexpectedly inflate,
          # and we ensure we have proper logical support throughout the codebase for all fields.
          const :dynamic, T.nilable(Dynamic), default: Dynamic::Strict
          const :properties, T::Hash[Symbol, FieldDataType], default: {}
          const :enabled, T.nilable(T::Boolean)
          const :custom_field_type, T.nilable(T.any(FieldDataTypeName::Object, FieldDataTypeName::Nested))

          sig { override.returns(FieldDataTypeName) }
          def name
            local_custom_field_type = custom_field_type
            return local_custom_field_type unless local_custom_field_type.nil?
            FieldDataTypeName::Object
          end

          sig { override.returns(T::Hash[T.untyped, T.untyped]) }
          def to_hash
            hashed_properties = properties.each_with_object({}) { |(name, field), result| result[name] = field.to_hash } unless properties.empty?
            {
              type: custom_field_type&.serialize,
              enabled: enabled,
              # If an object is not enabled for indexing, dynamic (an indexing directive) must be nil.
              # Otherwise the mapping operation will fail.
              dynamic: enabled != false ? dynamic&.serialize : nil,
              properties: hashed_properties
            }.compact
          end
        end
      end
    end
  end
end
