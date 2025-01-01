# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class InvalidResponseContentError < OpenApi::Validation::Error
      code :invalid_response_content

      def initialize(operation, body)
        @operation = operation
        @body = body
        super(@operation, ["responses"])
      end

      def public_message
        "expected an empty response but got #{@body}"
      end

      def developer_message
        <<~MD
        #{public_message}

        The request failed because it returned an unexpected body:

        - #{@body}

        Either change the endpoint response or add it to the Open API schema.
        MD
      end
    end
  end
end
