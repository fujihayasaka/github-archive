# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class MissingRequiredPathParameterError < OpenApi::Validation::Error
      code :missing_path_parameter

      def initialize(parameter)
        @parameter = parameter
        super(@parameter.schema, @parameter.json_pointer)
      end

      def public_message
        "Missing required path parameter #{@parameter.name}"
      end

      def developer_message
        <<~MD
        The request failed because a required parameter was missing from the request path:

        - #{@parameter.name}

        Either add the parameter to the request or remove its `required:` attribute from the OpenAPI operation.
        MD
      end
    end
  end
end
