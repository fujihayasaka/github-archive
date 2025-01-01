# typed: true
# frozen_string_literal: true
module OpenApi
  module Validation
    class ResponseValidator
      attr_reader :settings

      # @param operation [OpenApi::Description::Operation]
      # @param validation_settings [OpenApi::Description::ResponseValidationSetting]
      def initialize(operation:, validation_settings:)
        @operation = operation
        @settings = validation_settings
      end

      # Validates a HTTP response against an OpenAPI operation
      # @param status [Integer]
      # @param headers [Array<Header>]
      # @param body [Array<String>]
      # @returns [OpenApi::Validation::ValidationResult]
      def validate(status, headers, body)
        return OpenApi::Validation::ValidationResult.valid if @operation.responses.nil?

        body = body.first

        if !@operation.responses.has_status?(status)
          error = OpenApi::Validation::InvalidResponseStatusError.new(@operation, status)
          return OpenApi::Validation::ValidationResult.from_error(error)
        end

        content = @operation.responses.content_for(status)

        if content.nil?
          # for some reason, we also consider "{}" an empty response
          if body.nil? || body.empty? || body == "{}"
            return OpenApi::Validation::ValidationResult.valid
          else
            error = OpenApi::Validation::InvalidResponseContentError.new(@operation, body)
            return OpenApi::Validation::ValidationResult.from_error(error)
          end
        end

        media_type = settings.response_media_type_override
        media_type ||= headers["Content-Type"].split(";").first

        unless content.key?(media_type)
          error = OpenApi::Validation::UnsupportedResponseMediaTypeError.new(@operation, media_type, content.keys)
          return OpenApi::Validation::ValidationResult.from_error(error)
        end

        schema = @operation.responses.schema_for(status: status, media_type: media_type)

        # If there's no schema, it means the description either isn't JSON or no content type has been defined
        # In either case, for now we let it through and don't validate it
        return OpenApi::Validation::ValidationResult.valid if !schema


        json_pointer = ["responses", status, "content", json_pointer_escape(media_type), "schema"]

        validator = OpenApi::Validation::SchemaValidator.new(
          schema,
          json_pointer,
          disable_additional_properties: settings.disable_additional_properties?
        )

        json = GitHub::JSON.parse(body)
        validator.validate(json)
      end

      private

      def json_pointer_escape(segment)
        segment.gsub("/", "^/")
      end
    end
  end
end
