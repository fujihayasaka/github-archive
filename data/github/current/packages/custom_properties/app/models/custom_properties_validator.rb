# typed: strict
# frozen_string_literal: true

module CustomPropertiesValidator
  extend T::Sig
  extend self

  include Kernel

  include CustomProperties
  include CustomProperties::Errors
  include GitHub::Memoizer

  sig { params(definitions_hash: T::Hash[String, IPropertyDefinition], properties: T::Hash[String, PropertyValue]).returns(T::Array[SchemaValidationError]) }
  def validate_properties(definitions_hash, properties)
    errors = validate_schema(definitions_hash, properties) + validate_values(properties)
    errors.uniq { |e| e.error_message }
  end

  sig { params(value: String).returns(String) }
  def value_invalid_chars(value)
    invalid_chars = value.scan(Public::VALUE_INVALID_CHARS_REGEX)
    invalid_chars.uniq.join(", ")
  end

  sig { params(property_name: String, value_type: String, allowed_values: T.nilable(T::Array[String]), value: T.untyped).returns(T::Array[SchemaValidationError]) }
  def validate_allowed_values(property_name, value_type, allowed_values, value)
    allowed_values = value_type == "true_false" ? %w[true false] : allowed_values
    return [] unless allowed_values.present?

    invalid_values = Array(value) - allowed_values
    if invalid_values.present?
      message = "#{"Value".pluralize(invalid_values.size)} '#{invalid_values.join(", ")}' #{"is".pluralize(invalid_values.size)} not allowed for property '#{property_name}'"
      return [SchemaValidationError.new(property_name, message)]
    end

    []
  end

  private

  sig { params(definitions_hash: T::Hash[String, IPropertyDefinition], properties: T::Hash[String, PropertyValue]).returns(T::Array[SchemaValidationError]) }
  def validate_schema(definitions_hash, properties)
    errors = T.let([], T::Array[SchemaValidationError])

    properties.each_pair do |name, value|
      definition = definitions_hash[name]
      next errors << SchemaValidationError.new(name, "Unexpected property '#{name}'") if definition.nil?
      next if value.blank?

      value_type_errors = validate_value_type(definition, value)
      errors += value_type_errors
      # If value type is invalid, we don't need to bother performing other checks.
      errors += validate_allowed_values(definition.property_name, definition.value_type, definition.allowed_values, value) if value_type_errors.empty?

      regex = definition&.regex
      if regex && value.is_a?(String)
        errors << SchemaValidationError.new(name, "Property '#{name}' must match regular expression #{regex}") unless regex_validator.matches?(value, regex)
      end
    end

    errors
  end

  sig { params(properties: T::Hash[String, PropertyValue]).returns(T::Array[SchemaValidationError]) }
  def validate_values(properties)
    errors = T.let([], T::Array[SchemaValidationError])
    errors = properties.flat_map do |property_name, property_value|
      Array(property_value).flat_map { |value| validate_single_value(property_name, value) }
    end

    errors
  end

  sig { params(definition: IPropertyDefinition, value: T.untyped).returns(T::Array[SchemaValidationError]) }
  def validate_value_type(definition, value)
    property_name = definition.property_name

    if definition.multi_select_value_type?
      return [SchemaValidationError.new(property_name, "Property '#{property_name}' value must be a list of strings")] unless value.is_a?(Array)

      has_duplicate_values = value.uniq.length != value.length
      return [SchemaValidationError.new(property_name, "Property '#{property_name}' values must be distinct")] if has_duplicate_values
    else
      return [SchemaValidationError.new(property_name, "Property '#{property_name}' values must be strings")] unless value.is_a?(String)
    end

    []
  end

  sig { params(property_name: String, value: T.untyped).returns(T::Array[SchemaValidationError]) }
  def validate_single_value(property_name, value)
    errors = []

    case value
    when String
      unless value.size <= Public::MAX_LENGTH
        errors << SchemaValidationError.new(property_name, "Property '#{property_name}' value is too long")
      end

      invalid_chars = value_invalid_chars(value)
      unless invalid_chars.empty?
        errors << SchemaValidationError.new(property_name, "Property '#{property_name}' value has invalid characters: #{invalid_chars}")
      end
    else
      errors << SchemaValidationError.new(property_name, "Property '#{property_name}' values must be strings")
    end

    errors
  end

  sig { returns(Regex::RE2Helper) }
  memoize def regex_validator
    Regex::RE2Helper.new
  end
end
