# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class InvalidResponseStatusError < OpenApi::Validation::Error
      code :invalid_response_status

      def initialize(operation, status)
        @operation = operation
        @status = status
        super(@operation, ["responses"])
      end

      def public_message
        "no response with status #{@status} was defined for operation #{@operation.id}"
      end

      def developer_message
        <<~MD
        #{public_message}

        The request failed because it returned an unexpected status:

        - #{@status}

        Either change the endpoint to respond with a status which already has a schema or add a new schema to the Open API operation for this status.
        MD
      end
    end
  end
end
