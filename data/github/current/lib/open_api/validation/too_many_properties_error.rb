# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class TooManyPropertiesError < OpenApi::Validation::SchemaError
      code :invalid_max_properties

      def public_message
        "Object has too many properties. Provided: `#{data.keys.size}` Max: `#{object.max_properties}`"
      end

      def developer_message
        <<~MD
        Too many parameters were given at `#{description_pointer}`. #{data.keys.size} were given, but only #{object.max_properties} are allowed. To fix this, either:

        - Remove some properties from the value, so that the `maxProperties:` setting is respected,
        - Or, update the `maxProperties:` configuration to accomodate values like this one.
        MD
      end
    end
  end
end
