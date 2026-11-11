# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class InvalidAdditionalPropertiesError < SchemaError
      code :invalid_additional_properties

      def initialize(schema, data, description_path:, data_path:, additional_properties:)
        super(schema, data, description_path: description_path, data_path: data_path)
        @additional_properties = additional_properties
      end

      def public_message
        if @additional_properties.length == 1
          "#{@additional_properties.first.inspect} is not a permitted key."
        else
          "#{@additional_properties.map(&:inspect).join(', ')} are not permitted keys."
        end
      end

      def developer_message
        <<~ERR
       Some properties not defined by the schema were found in runtime data:

       #{@additional_properties.map(&:inspect).join(', ')}

       To fix this error:

       - Remove the extra properties from the serializer or provided data.
       - Or, if they are valid, add the properties to the schema
        ERR
      end
    end
  end
end
