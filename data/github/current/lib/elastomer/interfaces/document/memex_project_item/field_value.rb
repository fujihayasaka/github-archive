# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Document
      module MemexProjectItem
        class FieldValue < T::Struct
          prop :field_slug, String
          prop :field_type, String

          # The canonical identifier that is used to match the current project field.
          prop :field_id, MemexProjectItem::FieldValues::FieldIdProperty

          # The name of the key in the `field_values` object that contains the field value.
          prop :value_name, Symbol

          # The value used to match the `value_name` field in the `field_values` object within the Elasticsearch
          # document.
          prop :value, Value

          sig { returns(T::Hash[T.untyped, T.untyped]) }
          def to_hash
            # HACK: Use introspection to determine if the value is still an unserialized object, and then serialize
            # it if necessary. Ideally, all values would implement an interface that would allow us to serialize them
            # without runtime introspection, but such an interface doesn't exist yet.
            #
            # This will be removed with https://github.com/github/projects-backend/issues/673.
            serialized_value = if value.respond_to?(:to_hash)
              T.unsafe(value).to_hash
            elsif value.is_a?(Array) && T.cast(value, T::Array[T.untyped]).first.respond_to?(:to_hash)
              T.unsafe(value).map(&:to_hash)
            else
              value
            end

            {
              :field_slug => field_slug,
              :field_type => field_type,
              field_id.property => field_id.id,
              value_name => serialized_value,
            }
          end
        end
      end
    end
  end
end
