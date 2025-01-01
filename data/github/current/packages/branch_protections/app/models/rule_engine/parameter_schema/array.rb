# typed: true
# frozen_string_literal: true

module RuleEngine
  module ParameterSchema
    class Array < Base

      attr_reader :content_type, :content_object

      def initialize(name:, display_name:, description:, required: false, content_type:, content_object: nil, org_only: false,
        internal: false, supported_plan: nil, default_value: nil, validator: nil, ui_control: nil, visibility_fn: nil,
        feature_flag: nil, min_ghes_version: nil, beta: false, beta_api: false, publish_api: nil, description_api: nil, aliases: [], transform_fn: nil)
        super(type: "array", name:, display_name:, description:, required:,
          org_only:, internal:, supported_plan:, default_value:,
          validator:, ui_control:, visibility_fn:, feature_flag:,
          min_ghes_version:, beta:, beta_api:, publish_api:, description_api:, aliases:, transform_fn:)
        @content_type = content_type
        @content_object = content_object
      end

      def graphql_content_type
        Field::GRAPHQL_TYPES[content_type]
      end

      def validate_parameters(context, param_value)
        errors = []

        if param_value.is_a?(::Array)
          if content_type == :object
            current_context = ValidationContext.new(context.root, param_value)
            param_value.each_with_index do |value, index|
              sub_errors = content_object.validate_parameters(current_context, value)
              if sub_errors.any?
                errors << {
                  error_code: :invalid_content,
                  message: "Invalid array of #{content_object.name} objects: #{sub_errors.map { |e| e[:message] }.join(", ")}",
                  index: index,
                  sub_errors:,
                }
              end
            end
          else
            classes = Field::CLASS_TYPES[content_type]
            param_value.each_with_index do |array_element, index|
              if !classes&.include?(array_element.class)
                errors << {
                  error_code: :unexpected_content_type,
                  message: "Expected array of #{content_type}, found element of type #{array_element.class}",
                  index: index
                }
              end
            end
          end

          apply_custom_validator(context, param_value, errors)
        else
          errors << { error_code: :unexpected_type, message: "Expected array, got #{param_value.class}" }
        end

        errors
      end
    end
  end
end
