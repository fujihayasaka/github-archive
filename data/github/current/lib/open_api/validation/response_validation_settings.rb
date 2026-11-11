# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    # Configuration for OpenAPI::Validator which helps validating in different contexts
    class ResponseValidationSettings
      def self.default
        new
      end

      attr_accessor :disable_additional_properties
      alias_method :disable_additional_properties?, :disable_additional_properties
      attr_accessor :response_media_type_override

      def initialize(
        disable_additional_properties: true,
        response_media_type_override: nil
      )
        @disable_additional_properties = disable_additional_properties
        @response_media_type_override = response_media_type_override
      end
    end
  end
end
