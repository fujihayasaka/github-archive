# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class UnsupportedQueryParameterError < OpenApi::Validation::Error
      code :unsupported_query_parameter

      def initialize(operation, parameter)
        @operation = operation
        @parameter = parameter
        super(@operation, ["parameters"])
      end

      def public_message
        "Unsupported query parameter #{@parameter}"
      end

      def developer_message
        <<~MD
        The request failed because an unsupported query parameter was supplied with the request:

        - #{@parameter}

        Either remove the query parameter from the request or add it to the Open API schema.
        MD
      end
    end
  end
end
