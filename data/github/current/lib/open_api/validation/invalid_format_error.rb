# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class InvalidFormatError < OpenApi::Validation::SchemaError
      code :invalid_format

      def public_message
        "#{@data.inspect} is not a valid #{@object.format}"
      end

      def developer_message
        <<~ERR
        Expected data to be of format `#{@object.format}`, but received the value `#{@data.inspect}`. To fix this, either:

        - If it's an existing property, change the schema's format to match the data's format.
        - If this is a new property, modify the serializer so the data matches the specified format.
        ERR
      end
    end
  end
end
