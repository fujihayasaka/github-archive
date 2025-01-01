# typed: true
# frozen_string_literal: true

module RuleEngine
  module ParameterSchema
    class Object < Base
      extend T::Sig

      sig { params(validator: T.untyped, transform_fn: T.untyped, ui_options: T.untyped).returns(RuleEngine::ParameterSchema::Object) }
      def self.root(validator: nil, transform_fn: nil, ui_options: {})
        new(name: nil, display_name: nil, description: nil, required: true, root: true, validator:, ui_options:, transform_fn:)
      end

      def self.empty_schema
        root
      end

      sig { returns(T::Array[RuleEngine::ParameterSchema::Base]) }
      attr_reader :fields

      attr_reader :ui_options

      def initialize(name:, display_name:, description:, required: false, root: false, org_only: false, internal: false,
                    supported_plan: nil, default_value: nil, validator: nil, ui_control: nil, visibility_fn: nil, feature_flag: nil,
                    min_ghes_version: nil, beta: false, beta_api: false, publish_api: nil, description_api: nil, ui_options: {}, aliases: [], transform_fn: nil)
        super(type: "object", name:, display_name:, description:, required:, root:,
              org_only:, internal:, supported_plan:, default_value:,
              validator:, ui_control:, visibility_fn:, feature_flag:, publish_api:,
              min_ghes_version:, beta:, beta_api:, description_api:, aliases:, transform_fn:)
        @fields = []
        @ui_options = ui_options
      end

      def add_field(field)
        if fields.find { |existing| existing.name == field.name || existing.aliases.include?(field.name) }
          raise DuplicateFieldError.new("Duplicate field #{field.name}")
        end
        @fields << field
      end

      def empty?
        fields.empty?
      end

      def has_visible_fields?
        fields.any? && !fields.all?(&:internal)
      end

      def validate_parameters(context, params)
        errors = []

        if params.is_a?(Hash)
          fields.each do |field|
            if params.has_key?(field.name)
              current_context = ValidationContext.new(context.root, params)
              field_errors = field.validate_parameters(current_context, params[field.name])
              if field_errors.any?
                if field.is_a?(Array) || field.is_a?(Object)
                  errors << {
                    error_code: :invalid,
                    message: "Invalid parameter #{field.name}: #{field_errors.map { |e| e[:message] }.join(", ")}",
                    sub_errors: field_errors,
                    field: field.name
                  }
                else
                  errors << {
                    error_code: :invalid,
                    message: field_errors.map { |e| e[:message] }.join(", "),
                    field: field.name
                  }
                end
              end
            elsif field.required
              errors << {
                error_code: :missing,
                message: "Missing required parameter `#{field.name}`",
                field: field.name
              }
            end
          end

          params.each do |key, _value|
            if fields.none? { |f| f.name == key }
              errors << {
                error_code: :unexpected_field,
                message: "Unexpected parameter `#{key}`",
                value: key
              }
            end
          end

          apply_custom_validator(context, params, errors)
        else
          errors << {
            error_code: :unexpected_type,
            message: "Expected object, got #{params.class}",
            value: params.class
          }
        end

        errors
      end

      def apply_defaults_for_source(source, params)
        @fields.each do |field|
          set_default = false

          if !field.is_visible_by_source?(source)
            set_default = true
          elsif !field.default_value.nil? && !params.key?(field.name)
            set_default = true
          end

          next unless set_default

          params[field.name] = field.default_value
        end
      end

      class DuplicateFieldError < StandardError; end
    end
  end
end
