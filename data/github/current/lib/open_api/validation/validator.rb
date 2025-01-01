# typed: true
# frozen_string_literal: true

#

module OpenApi
  module Validation
    class Validator

      class NoRouteMatchFoundError < StandardError; end

      attr_reader :result

      def initialize(
        request,
        operation,
        validate_path_parameters: true,
        validate_query_parameters: true,
        validate_request_body: true,
        validate_extra_query_parameters: true,
        allow_skipping_validation: false,
        disable_additional_properties: true,
        response_media_type_override: nil
      )
        @request   = request
        @operation = operation
        @result    = OpenApi::Validation::ValidationResult.valid

        @request_validation_settings = OpenApi::Validation::RequestValidationSettings.new(
          validate_path_parameters: validate_path_parameters,
          validate_query_parameters: validate_query_parameters,
          validate_request_body: validate_request_body,
          validate_extra_query_parameters: validate_extra_query_parameters,
          allow_skipping_validation: allow_skipping_validation,
        )

        @response_validation_settings = OpenApi::Validation::ResponseValidationSettings.new(
          disable_additional_properties: disable_additional_properties,
          response_media_type_override: response_media_type_override,
        )
      end

      def validate_request
        Api::InstrumentSegment.call(@request.env, "openapi.validation.validate_request") do
          return result if !@operation.present? || @operation.ignored?

          versioned_operation = OpenApi::Description::VersionedOperation.new(
            @operation.raw,
            @request.env[Api::SelectedVersion::ENV_REQUESTED_API_VERSION]
          )

          validator = OpenApi::Validation::RequestValidator.new(
            operation: versioned_operation,
            validation_settings: @request_validation_settings
          )

          original_path = @request.env[GitHub::Routers::Api::ORIGINAL_PATH_INFO]
          if original_path
            route_match = Router.match(request_path: original_path, operation: @operation)
          end

          # We do some crazy PATH_INFO rewrites in GitHub::Routers::Api
          # so lets check the modified path if no match is found from
          # the original.
          route_match ||= Router.match(request_path: @request.path, operation: @operation)

          if route_match
            request_result = validator.validate(@request, route_match.parameters)
          else
            raise NoRouteMatchFoundError, "request path: #{@request.path}, operation id: #{@operation.id}, operation path: #{@operation.path}, original path: #{original_path}"
          end

          # We are skipping any path parameter errors that are a result from
          # calling the `api` test helper method with the id-based path rather
          # than the resource-based path.  Any other schema validations will run
          # on the remainder of the path parameters.
          if request_result.errors.any? && route_match.matched_alt_path?
            request_result.errors.delete_if { |error| error.is_a?(MissingRequiredPathParameterError) }
          end

          result.add_errors(request_result.errors)

          request_result
        end
      end

      def validate_response(status, headers, body)
        Api::InstrumentSegment.call(@request.env, "openapi.validation.validate_response") do
          return result if !@operation.present? || @operation.ignored?

          versioned_operation = OpenApi::Description::VersionedOperation.new(
            @operation.raw,
            @request.env[Api::SelectedVersion::ENV_REQUESTED_API_VERSION]
          )

          validator = OpenApi::Validation::ResponseValidator.new(
            operation: versioned_operation,
            validation_settings: @response_validation_settings
          )
          response_result = validator.validate(status, headers, body)

          result.add_errors(response_result.errors)

          response_result
        end
      end
    end
  end
end
