# typed: true
# frozen_string_literal: true

module RuleEngine
  module ParameterSchema
    class Object < Base
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
                    supported_plan: nil, default_value: nil, apply_default_on_load: false, validator: nil, ui_control: nil, visibility_fn: nil, feature_flag: nil,
                    min_ghes_version: nil, beta: false, beta_api_note: false, publish_api: nil, description_api: nil, ui_options: {}, aliases: [], transform_fn: nil)
        super(type: "object", name:, display_name:, description:, required:, root:,
              org_only:, internal:, supported_plan:, default_value:, apply_default_on_load:,
              validator:, ui_control:, visibility_fn:, feature_flag:, publish_api:,
              min_ghes_version:, beta:, beta_api_note:, description_api:, aliases:, transform_fn:)
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

      sig { params(source: T.nilable(Types::RuleSource), params: T::Hash[T.untyped, T.untyped], on_load: T::Boolean).void }
      def apply_defaults_for_source(source, params, on_load: false)
        @fields.each do |field|
          set_default = false

          if source && !field.is_visible_by_source?(source)
            set_default = true
          elsif !field.default_value.nil? && !params.key?(field.name)
            set_default = true
          end

          unless set_default
            # If the field is an object or array, we should apply defaults to its children if any exist
            if params[field.name].is_a?(Hash) && field.is_a?(Object)
              field.apply_defaults_for_source(source, params[field.name], on_load:)
            elsif params[field.name].is_a?(::Array) && field.is_a?(Array) && field.content_type == :object
              params[field.name].each do |item|
                next unless item.is_a?(Hash)
                field.content_object.apply_defaults_for_source(source, item, on_load:)
              end
            end
          end

          next if on_load && !field.apply_default_on_load
          next unless set_default

          params[field.name] = field.default_value
        end
      end

      # Iterates over all fields in the object schema, yielding each field along with its value
      # from the parameters hash and the parent hash containing that value
      sig { params(parameters: T::Hash[T.untyped, T.untyped], blk: T.proc.params(field: Base, value: T.untyped, parent: T::Hash[T.untyped, T.untyped]).void).void }
      def walk_fields(parameters, &blk)
        fields.each do |field|
          next unless parameters.key?(field.name)
          if field.is_a?(RuleEngine::ParameterSchema::Array) && field.content_type == :object && parameters[field.name].is_a?(::Array)
            parameters[field.name].each do |item|
              field.content_object.walk_fields(item, &blk) if item.is_a?(Hash)
            end
          elsif field.is_a?(RuleEngine::ParameterSchema::Object)
            field.walk_fields(parameters[field.name], &blk) if parameters[field.name].is_a?(Hash)
          else
            yield(field, parameters[field.name], parameters)
          end
        end
      end

      # Iterates over all parameters grouped by their schema and removes any invalid node IDs
      sig { params(parameters_by_schema: T::Hash[Object, T::Hash[String, T.untyped]]).void }
      def self.batch_delete_invalid_node_ids(parameters_by_schema)
        # Generate a list of procs that can be used later on to remove invalid node IDs from parameter hashes
        deleters_by_node_id = Hash.new { |h, k| h[k] = [] }
        parameters_by_schema.each do |schema, parameters|
          schema.walk_fields(parameters) do |field, value, parent|
            if field.is_a?(RuleEngine::ParameterSchema::NodeIdField)
              next unless field.valid_types&.any? # only validate if there are valid types specified
              next unless value.is_a?(String) && value.present?
              deleters_by_node_id[value] << -> do
                parent[field.name] = nil
              end
            elsif field.is_a?(RuleEngine::ParameterSchema::Array) && field.content_type == :node_id && value.is_a?(::Array)
              next unless field.node_id_valid_types&.any? # only validate if there are valid types specified
              value.each do |item|
                next unless item.is_a?(String) && item.present?
                deleters_by_node_id[item] << -> do
                  parent[field.name] = parent[field.name]&.reject { |v| v == item }
                end
              end
            end
          end
        end

        node_ids_to_check = deleters_by_node_id.keys.to_set
        valid_node_ids = NodeIdField.valid_node_ids(node_ids_to_check)
        invalid_node_ids = node_ids_to_check - valid_node_ids

        # Call the deleter procs for any invalid node IDs to remove them from the parameter hashes
        deleters_by_node_id.each do |node_id, deleters|
          next unless invalid_node_ids.include?(node_id)

          deleters.each(&:call)
        end
      end

      class DuplicateFieldError < StandardError; end
    end
  end
end
