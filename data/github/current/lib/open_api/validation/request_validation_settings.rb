# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    # Configuration for OpenAPI::Validator which helps validating in different contexts
    class RequestValidationSettings
      def self.default
        new
      end

      attr_accessor :validate_path_parameters
      attr_accessor :validate_query_parameters
      attr_accessor :validate_request_body
      attr_accessor :validate_extra_query_parameters
      attr_accessor :allow_skipping_validation

      alias_method :validate_path_parameters?, :validate_path_parameters
      alias_method :validate_query_parameters?, :validate_query_parameters
      alias_method :validate_request_body?, :validate_request_body
      alias_method :validate_extra_query_parameters?, :validate_extra_query_parameters
      alias_method :allow_skipping_validation?, :allow_skipping_validation

      def initialize(
        validate_path_parameters: true,
        validate_query_parameters: true,
        validate_request_body: true,
        validate_extra_query_parameters: true,
        allow_skipping_validation: false
      )
        @validate_path_parameters = validate_path_parameters
        @validate_query_parameters = validate_query_parameters
        @validate_request_body = validate_request_body
        @validate_extra_query_parameters = validate_extra_query_parameters
        @allow_skipping_validation = allow_skipping_validation
      end
    end
  end
end
