# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class InvalidPatternError < OpenApi::Validation::SchemaError
      code :invalid_pattern

      def public_message
        "#{data} does not match `#{object.pattern.inspect}`."
      end

      def developer_message
        <<~ERR
        The request failed because the value supplied #{data.inspect} does not match `#{object.pattern.inspect}`."

        To fix this, either:

        - Change the schema's pattern to match the value found here
        - Update the code so that it uses a value that matches the schema pattern
        ERR
      end
    end
  end
end
