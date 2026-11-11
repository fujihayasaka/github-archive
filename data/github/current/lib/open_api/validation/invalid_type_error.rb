# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class InvalidTypeError < OpenApi::Validation::SchemaError
      code :invalid_type

      def public_message
        "`#{data.inspect}` is not of type `#{object.type}`."
      end

      def developer_message
        <<~ERR
        `#{description_pointer}` expected type `#{object.type}`, but received the value `#{data.inspect}`. To fix this, either:

        - Change the schema's type to match the value found here
        - Update the code so that it uses a type that matches the schema
        - Use `oneOf:` to support multiple types in this schema
        ERR
      end
    end
  end
end
