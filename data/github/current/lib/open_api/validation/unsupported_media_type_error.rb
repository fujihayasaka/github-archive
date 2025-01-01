# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class UnsupportedMediaTypeError < OpenApi::Validation::Error
      code :unsupported_media_type

      def initialize(operation, media_type)
        @operation = operation
        @media_type = media_type
        super(@operation.request_body, ["requestBody"])
      end

      def public_message
        "Unsupported media type #{@media_type}"
      end

      def developer_message
        <<~MD
        The request failed because an unsupported media type was supplied with the request:

        - #{@media_type}

        Either remove the media type from the request or add it to the Open API schema.
        MD
      end
    end
  end
end
