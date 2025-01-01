# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class RequestValidator
      attr_reader :settings

      # These are deprecated query parameters that could be used on any operation
      # When they're passed, don't validate them as this would bloat the spec too much
      # to include them.
      GLOBAL_PARAMETERS = %w[client_id client_secret oauth_credential_ratelimit_increase].freeze

      # @param operation [OpenApi::Description::Operation]
      # @param validation_settings [OpenApi::Validation::ValidationSettings]
      def initialize(operation:, validation_settings:)
        @operation = operation
        @settings  = validation_settings

        if !@operation.version_applied?
          raise ArgumentError, "You can only pass in an operation that has already had a version applied."
        end
      end

      # Validates a rack request against an OpenAPI operation
      # @param request [Rack::Request]
      # @param path_parameters [Array<TODO>]
      # @returns [OpenApi::Validation::ValidationResult]
      def validate(request, path_parameters)
        errors = []

        if settings.validate_path_parameters?
          validate_path_parameters(path_parameters, errors)
        end

        if settings.validate_query_parameters?
          validate_query_parameters(request, errors)
        end

        if settings.validate_request_body?
          validate_request_body(request, errors)
        end

        OpenApi::Validation::ValidationResult.new(errors)
      end

      private

      def validate_path_parameters(request_params, errors)
        @operation.path_parameters.each do |name, parameter|
          if request_params.key?(name)
            validator = OpenApi::Validation::SchemaValidator.new(
              parameter.schema,
              parameter.json_pointer,
              coerce_values: true
            )
            errors.push(*validator.validate(request_params[name]).errors)
          elsif parameter.required?
            errors << OpenApi::Validation::MissingRequiredPathParameterError.new(parameter)
          end
        end
      end

      def validate_query_parameters(request, errors)
        request_params = request.GET

        @operation.query_parameters.each do |name, parameter|
          if request_params.key?(name)
            validator = OpenApi::Validation::SchemaValidator.new(
              parameter.schema,
              parameter.json_pointer,
              coerce_values: true
            )
            errors.push(*validator.validate(request_params[name]).errors)
          elsif parameter.required?
            errors << OpenApi::Validation::MissingRequiredQueryParameterError.new(parameter)
          end
        end

        if settings.validate_extra_query_parameters?
          request_params.each do |key, _value|
            if !@operation.query_parameters[key]
              next if GLOBAL_PARAMETERS.include?(key)
              errors << OpenApi::Validation::UnsupportedQueryParameterError.new(@operation, key)
            end
          end
        end
      end

      def validate_request_body(request, errors)
        return if @operation.request_body.nil?

        media_type = request.media_type
        json = nil

        # We still try to parse JSON
        if valid_as_json?(media_type)
          request.body.rewind

          begin
            json = GitHub::JSON.parse(request.body.read)
            media_type = "application/json"
          rescue Yajl::ParseError, StandardError # rubocop:todo Lint/GenericRescue
            nil
          end

          request.body.rewind
        end

        if !@operation.request_body.content.key?(media_type) && !skip_media_type_check?(request.media_type)
          errors << OpenApi::Validation::UnsupportedMediaTypeError.new(@operation, request.media_type)
          return
        end

        # Can't validate anything else than JSON for now
        return if media_type != "application/json"

        json_pointer = ["requestBody", "content", json_pointer_escape(@operation.request_body.content.keys.first), "schema"]
        schema = @operation.request_body.schema

        validator = OpenApi::Validation::SchemaValidator.new(
          schema,
          json_pointer,
          allow_skipping_validation: settings.allow_skipping_validation?
        )

        result = validator.validate(json)
        errors.push(*result.errors)
      end

      def skip_media_type_check?(request_media_type)
        # Some tests dont set a request media type.
        # And application/x-www-form-urlencoded is the default POST media type for sinatra
        # Act as if this was OK during validation
        (request_media_type.nil? || request_media_type == "application/x-www-form-urlencoded")
      end

      def json_pointer_escape(segment)
        segment.gsub("/", "^/")
      end

      # Our API tries to parse JSON even with other content types
      JSON_LIKE_MEDIA_TYPES = ["text/plain", "application/json"].freeze

      def valid_as_json?(media_type)
        # Anything with +json
        return true if Api::MediaType.new(media_type).json?

        # Or media types we consider as JSON
        JSON_LIKE_MEDIA_TYPES.include?(media_type)
      end
    end
  end
end
