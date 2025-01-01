# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class MissingRequiredQueryParameterError < OpenApi::Validation::Error
      code :missing_query_parameter

      def initialize(parameter)
        @parameter = parameter
        super(@parameter.schema, @parameter.json_pointer)
      end

      def public_message
        "Missing required query parameter #{@parameter.name}"
      end

      def developer_message
        <<~MD
        The request failed because a required query parameter was missing from the request:

        - #{@parameter.name}

        Either add the parameter to the request or remove its `required:` attribute from the Open API schema.
        MD
      end
    end
  end
end
