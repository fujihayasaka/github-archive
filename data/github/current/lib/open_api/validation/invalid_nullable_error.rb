# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class InvalidNullableError < OpenApi::Validation::SchemaError
      code :invalid_nullable

      def public_message
        "data cannot be null."
      end

      def developer_message
        <<~ERR
        `#{description_pointer}` was `nil`, but it doesn't have `nullable: true`. To fix this, either:

        - Add `nullable: true` to the schema, so that `nil` is valid;
        - Or, update the code so that `nil` isn't used here.

        If the property is using a `$ref`, you can annotate it with `x-nullable-ref: true` instead of using `nullable`.
        ERR
      end
    end
  end
end
