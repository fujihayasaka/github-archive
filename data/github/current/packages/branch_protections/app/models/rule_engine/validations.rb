# typed: true
# frozen_string_literal: true

module RuleEngine
  module Validations
    extend T::Sig

    def validate_parameterized(parameterized, root: nil)
      context = RuleEngine::ParameterSchema::ValidationContext.new(root || parameterized.parameters, nil)
      parameter_schema.validate_parameters(context, parameterized.parameters)
    end

    sig { overridable.returns(RuleEngine::ParameterSchema::Object) }
    def parameter_schema
      RuleEngine::ParameterSchema::Object.empty_schema
    end

    sig { params(source: T.nilable(Types::RuleSource)).returns(RuleEngine::ParameterSchema::Object) }
    def parameter_schema_for_source(source)
      source_parameter_schema = parameter_schema

      fields = source_parameter_schema.fields.dup
      source_parameter_schema.fields.clear
      source_parameter_schema.fields.concat(visible_fields_for_source(fields, source))

      source_parameter_schema
    end

    sig { params(fields: T::Array[T.untyped], source: T.nilable(Types::RuleSource)).returns(T::Array[RuleEngine::ParameterSchema::Field]) }
    def visible_fields_for_source(fields, source)
      visible_fields = []

      fields.each do |field|
        next unless field.is_visible_by_source?(source)

        if field.respond_to?(:content_object) && !field.content_object.nil?
          child_fields = field.content_object.fields.dup
          field.content_object.fields.clear
          field.content_object.fields.push(*visible_fields_for_source(child_fields, source))
        end

        visible_fields << field
      end

      visible_fields
    end

    # Renames aliases params and transforms field values when applicable
    sig { params(fields: T::Array[T.untyped], parameters: T::Hash[String, T.untyped]).void }
    def transform_parameters!(fields, parameters)
      # First perform any necessary transformation to the entire parameters hash
      parameter_schema.transform_parameters!(parameters)
      # Then transform individual values for fields, when applicable
      transform_parameter_fields!(fields, parameters)
    end

    sig { params(fields: T::Array[T.untyped], parameters: T::Hash[String, T.untyped]).void }
    def transform_parameter_fields!(fields, parameters)
      parameters.keys.each do |key|
        value = parameters[key]

        # Rename parameters that have aliases
        field = fields.find { |f| f.aliases.include?(key) }
        if field.present?
          parameters[field.name] = value
          parameters.delete(key)
        end

        # Find the field if we didn't already get it via the alias
        field = field || fields.find { |f| f.name == key }

        # Transform parameter values
        if field.present?
          parameters[field.name] = field&.transform_fn.present? ? field.transform_parameters(value) : value
        end

        # Rename nested parameter names
        if field.is_a?(ParameterSchema::Array) && field.content_type == :object && value.is_a?(::Array)
          value.filter { |item| item.is_a?(Hash) }.each do |item|
            transform_parameter_fields!(field.content_object.fields, item)
          end
        elsif field.is_a?(ParameterSchema::Object) && value.is_a?(Hash)
          transform_parameter_fields!(field.fields, value)
        end
      end
    end

    sig do
      params(
        context: RuleEngine::ParameterSchema::ValidationContext,
        params: T::Hash[T.untyped, T.untyped],
        errors: T::Array[T::Hash[T.untyped, T.untyped]])
      .void
    end
    def ensure_valid_include_exclude_condition(context, params, errors)
      # include and exclude cannot contain the same patterns
      invalid_patterns = []
      if params["include"].is_a?(::Array) && params["include"].size > 0 && params["exclude"].is_a?(::Array) && params["exclude"].size > 0
        params["include"].each do |include_pattern|
          # TODO: eventually we should add a way
          # to transform the values when they are set before validation
          include_pattern = include_pattern.strip
          params["exclude"].each do |exclude_pattern|
            exclude_pattern = exclude_pattern.strip
            invalid_patterns << exclude_pattern if exclude_pattern == include_pattern
          end
        end
      end

      return errors if invalid_patterns.empty?

      errors << {
        error_code: :invalid_pattern,
        message: "Target patterns found in both include and exclude parameters: `#{invalid_patterns.join("`, `")}`",
        value: invalid_patterns
      }
    end
  end
end
