# typed: true
# frozen_string_literal: true

module RuleEngine
  module ParameterSchema
    class Array < Base
      attr_reader :content_type, :content_object

      sig { returns(T.nilable(T::Array[{ display_name: String, value: String, description: T.nilable(String), warning: T.nilable(String), pinned: T::Boolean, docs_url: T.nilable(String) }])) }
      attr_reader :allowed_options

      sig { returns(T.nilable(T::Array[String])) }
      attr_reader :node_id_valid_types

      sig { returns(T.nilable(Object)) }
      attr_reader :node_id_object

      # TODO: Arrays should accept a "content_field" parameter instead of content_object + content_type to simplify validation and support complex array types
      def initialize(name:, display_name:, description:, required: false, content_type:, content_object: nil, node_id_valid_types: nil, node_id_object: nil, org_only: false,
        internal: false, supported_plan: nil, default_value: [], apply_default_on_load: false, validator: nil, ui_control: nil, visibility_fn: nil,
        min_elements: nil, max_elements: nil,
        feature_flag: nil, min_ghes_version: nil, beta: false, beta_api_note: false, publish_api: nil, description_api: nil, aliases: [], transform_fn: nil, allowed_options: nil,
        hidden_when: nil, clears_when: nil)
        super(type: "array", name:, display_name:, description:, required:,
          org_only:, internal:, supported_plan:, default_value:, apply_default_on_load:,
          validator:, ui_control:, visibility_fn:, feature_flag:,
          min_ghes_version:, beta:, beta_api_note:, publish_api:, description_api:, aliases:, transform_fn:,
          hidden_when:, clears_when:)
        @content_type = content_type
        @content_object = content_object
        @allowed_options = allowed_options
        @min_elements = min_elements
        @max_elements = max_elements
        @node_id_valid_types = node_id_valid_types
        @node_id_object = node_id_object

        if node_id_object
          raise "node_id_object is only valid when content_type is :node_id" if content_type != :node_id
          raise "Expect 1 id and 1 type field on node_id_object" if node_id_object.fields.map(&:name).sort != %w[id type]
        end
      end

      def graphql_content_type
        Field::GRAPHQL_TYPES[content_type]
      end

      def validate_parameters(context, param_value)
        errors = []

        if param_value.is_a?(::Array)
          if @min_elements && param_value.size < @min_elements
            errors << {
              error_code: :too_few_elements,
              message: "Expected at least #{@min_elements} elements, got #{param_value.size}",
            }
          end

          if @max_elements && param_value.size > @max_elements
            errors << {
              error_code: :too_many_elements,
              message: "Expected at most #{@max_elements} elements, got #{param_value.size}",
            }
          end

          if content_type == :object
            current_context = ValidationContext.new(context.root, param_value)
            param_value.each_with_index do |value, index|
              sub_errors = content_object.validate_parameters(current_context, value)
              if sub_errors.any?
                errors << {
                  error_code: :invalid_content,
                  message: "Invalid array contents. Errors at index #{index}: #{sub_errors.map { |e| e[:message] }.join(", ")}",
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
                  message: "Expected array of #{content_type}, found element of type #{array_element.class} at index #{index}",
                  index: index
                }
              end

              if allowed_options.present? && !T.must(allowed_options).any? { |o| o[:value] == array_element }
                errors << {
                  error_code: :invalid_content,
                  message: "Invalid option `#{array_element}` at index #{index}. Allowed options are #{T.must(allowed_options).map { |o| o[:value] }.join(", ")}",
                  index: index
                }
              end

              # TODO: Reuse NodeIdField when `content_field` is added
              if content_type == :node_id && array_element.is_a?(String) && array_element.present?
                result = begin
                  Platform::Helpers::GlobalId.parse(array_element)
                rescue Platform::Errors::NotFound
                  errors << { error_code: :invalid, message: "Invalid node ID format", index: index }
                  return errors
                end

                if (types = node_id_valid_types) && !types.include?(result&.type)
                  errors << { error_code: :invalid, message: "Invalid node type. Expected one of #{types.join(", ")}", index: index }
                end
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
