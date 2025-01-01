# typed: true
# frozen_string_literal: true

# TODO: Break this up into multiple field classes instead i.e. NumberField, StringField, etc
module RuleEngine
  module ParameterSchema
    class Field < Base

      GRAPHQL_TYPES = {
        string: "String",
        boolean: "Boolean",
        integer: "Integer",
        node_id: "ID"
      }

      CLASS_TYPES = {
        string: [String],
        boolean: [TrueClass, FalseClass],
        integer: [Integer],
        node_id: [String],
      }

      sig { returns(T.nilable(T::Array[{ display_name: String, value: String, description: T.nilable(String) }])) }
      attr_reader :allowed_options

      attr_reader :default_value, :allowed_values, :allowed_range, :ui_prefer_dropdown

      def initialize(name:, display_name:, type:, description:, required: false, allowed_options: nil, allowed_values: nil, allowed_range: nil,
                    org_only: false, internal: false, supported_plan: nil, default_value: nil, apply_default_on_load: false, validator: nil, ui_control: nil,
                    visibility_fn: nil, feature_flag: nil, min_ghes_version: nil, beta: false, beta_api_note: false, publish_api: nil, description_api: nil, ui_prefer_dropdown: true, aliases: [], transform_fn: nil)
        super(name:, display_name:, type:, description:, required:, internal:, org_only:, supported_plan:, default_value: calculate_default_value(type, required, default_value), apply_default_on_load:,
              validator:, ui_control:, visibility_fn:, feature_flag:, min_ghes_version:, beta:, beta_api_note:, publish_api:, description_api:, aliases:, transform_fn:)

        if allowed_options.present? && allowed_values.present?
          raise "Both allowed_options and allowed_values cannot be present at the same time"
        end

        if allowed_options.present?
          @allowed_options = allowed_options
          @allowed_values = allowed_options.map { |option| option[:value] }
        else
          @allowed_values = allowed_values
        end

        @allowed_range = allowed_range if type == :integer
        @ui_prefer_dropdown = ui_prefer_dropdown

        if type == :boolean && !required && default_value.nil? && !internal
          raise "Boolean fields must have a default value"
        end
      end

      def graphql_type
        GRAPHQL_TYPES[type]
      end

      def validate_parameters(context, param_value)
        errors = []

        if required && (param_value.nil? || (param_value.is_a?(String) && param_value.empty?))
          errors << { error_code: :missing, message: "Expected #{name} to be present" }
          return errors
        end

        classes = CLASS_TYPES[type]
        if classes.any? { |klass| param_value.is_a?(klass) }
          if @allowed_values && !@allowed_values.include?(param_value)
            errors << { error_code: :unexpected_value, message: "Expected value to be one of #{@allowed_values.join(", ")}, got #{param_value}" }
          end

          if @allowed_range && !@allowed_range.include?(param_value)
            errors << { error_code: :range_error, message: "Expected #{param_value} to be greater than #{@allowed_range.min}" } if @allowed_range.begin && !@allowed_range.end
            errors << { error_code: :range_error, message: "Expected #{param_value} to be less than #{@allowed_range.max}" } if @allowed_range.end && !@allowed_range.begin
            errors << { error_code: :range_error, message: "Expected #{param_value} to be between #{@allowed_range.min} and #{@allowed_range.max}" } if @allowed_range.begin && @allowed_range.end
          end

          apply_custom_validator(context, param_value, errors)
        elsif !param_value.nil?
          boolean_param_value = param_value.is_a?(TrueClass) || param_value.is_a?(FalseClass)

          unexpected_type_name = if boolean_param_value
            "boolean"
          else
            param_value.class.to_s.downcase.delete_suffix("class")
          end

          errors << { error_code: :unexpected_type, message: "Expected #{type}, got #{unexpected_type_name}" }
        end

        errors
      end

      private

      def calculate_default_value(type, required, default_value)
        return default_value unless required && default_value.nil?

        case type
        when :integer
          0
        when :string
          ""
        when :boolean
          false
        end
      end
    end
  end
end
