# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class UnsupportedResponseMediaTypeError < OpenApi::Validation::Error
      code :invalid_response_content_type

      def initialize(operation, requested_media_type, supported_media_types)
        @operation = operation
        @requested_media_type = requested_media_type
        @supported_media_types = supported_media_types
        super(@operation, ["responses"])
      end

      def public_message
        "Response media type not handled by operation, only found these supported media types: #{@supported_media_types}"
      end

      def developer_message
        <<~MD
        #{public_message}

        The request failed because the operation does not support the mediatype you requested: #{@requested_media_type}

        Either change the request to use a supported mediatype or change the operation to support the mediatype requested.
        MD
      end
    end
  end
end
