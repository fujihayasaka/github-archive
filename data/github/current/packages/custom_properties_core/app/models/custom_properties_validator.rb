# typed: strict
# frozen_string_literal: true

module CustomPropertiesValidator
  extend self

  include Kernel

  include CustomPropertiesCore
  include CustomPropertiesCore::Errors
  include GitHub::Memoizer

  VALID_ACTOR_TYPES = %w[user]
  VALID_SYSTEM_VALUE_TYPES = %w[string single_select multi_select url true_false]
  MAX_SYSTEM_PROPERTY_VALUE_LENGTH = 200

  sig do
    params(
      definitions: T::Array[IPropertyDefinition],
      properties: T::Hash[String, T.nilable(PropertyValue)],
      limits: PropertyLimits,
    ).returns(T::Array[SchemaValidationError])
  end
  def validate_properties(definitions, properties, limits:)
    definitions_hash = definitions.index_by(&:property_name).transform_keys(&:downcase)
    errors = validate_schema(definitions_hash, properties)

    if errors.empty?
      # At this point we can be sure that all property names are valid
      properties_with_definitions = properties.to_h { |name, value| [definitions_hash[name.downcase], value] }
      errors += validate_values(properties_with_definitions, limits)
    end

    errors.uniq { |e| e.error_message }
  end

  sig do
    params(
      property_name: String,
      value_type: String,
      allowed_values: T.nilable(T::Array[String]),
      value: T.nilable(PropertyValue),
    ).returns(T::Array[SchemaValidationError])
  end
  def validate_system_property(property_name, value_type, allowed_values, value)
    errors = T.let([], T::Array[SchemaValidationError])

    if VALID_SYSTEM_VALUE_TYPES.exclude?(value_type)
      return [SchemaValidationError.new(property_name, "Invalid value type '#{value_type}' for system property '#{property_name}'")]
    end

    return [] if value.blank?

    errors += validate_allowed_values(property_name, value_type, allowed_values, value)
    errors += validate_system_value_type(property_name, value_type, value)

    if errors.empty?
      errors = Array(value).flat_map { |value| validate_single_value(property_name, value, max_value_length: MAX_SYSTEM_PROPERTY_VALUE_LENGTH) }
    end

    errors
  end

  sig { params(value: String).returns(String) }
  def value_invalid_chars(value)
    invalid_chars = value.scan(Public::VALUE_INVALID_CHARS_REGEX)
    invalid_chars.uniq.join(", ")
  end

  sig { params(property_name: String, value_type: String, allowed_values: T.nilable(T::Array[String]), value: PropertyValue).returns(T::Array[SchemaValidationError]) }
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

  # Checks whether the supplied URL is valid to be saved for a URL property.
  # Adapted from packages/apps/app/models/integration_url.rb
  sig { params(url: T.nilable(PropertyValue)).returns(T.nilable(String)) }
  def invalid_url?(url)
    return "URL was not provided" unless url && url.is_a?(String)
    return "Invalid URL format" unless uri = Addressable::URI.parse(url)

    return "URL must be absolute" unless uri.absolute?

    return "URL scheme must be http or https" unless %w(http https).include?(uri.scheme)

    return "URL username/password are not allowed" if uri.userinfo.present?

    "URL host must be present" unless uri.host.present?
  rescue Addressable::URI::InvalidURIError
    "Invalid URL format"
  end

  private

  sig { params(definitions_hash: T::Hash[String, IPropertyDefinition], properties: T::Hash[String, T.nilable(PropertyValue)]).returns(T::Array[SchemaValidationError]) }
  def validate_schema(definitions_hash, properties)
    errors = T.let([], T::Array[SchemaValidationError])

    properties.each_pair do |name, value|
      definition = definitions_hash[name.downcase]
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

  sig do
    params(
      properties: T::Hash[IPropertyDefinition, T.nilable(PropertyValue)],
      limits: PropertyLimits,
    ).returns(T::Array[SchemaValidationError])
  end
  def validate_values(properties, limits)
    errors = T.let([], T::Array[SchemaValidationError])
    errors = properties.flat_map do |definition, property_value|
      next [] if property_value.nil?
      max_value_length = limits.max_property_value_length_by_type(definition.value_type)
      Array(property_value).flat_map { |value| validate_single_value(definition.property_name, value, max_value_length:) }
    end

    errors
  end

  # We don't type value as PropertyValue here because we want to allow invalid types to be passed in so that we can return the appropriate error messages.
  sig { params(definition: IPropertyDefinition, value: T.untyped).returns(T::Array[SchemaValidationError]) }
  def validate_value_type(definition, value)
    property_name = definition.property_name

    if definition.multi_select_value_type?
      return [SchemaValidationError.new(property_name, "Property '#{property_name}' value must be a list of strings")] unless value.is_a?(Array)

      has_duplicate_values = value.uniq.length != value.length
      return [SchemaValidationError.new(property_name, "Property '#{property_name}' values must be distinct")] if has_duplicate_values
    elsif definition.url_value_type?
      err = invalid_url?(value)
      return [SchemaValidationError.new(property_name, err)] if err
    elsif definition.actor_value_type?
      err = invalid_actor?(value, definition.source)
      return [SchemaValidationError.new(property_name, err)] if err.present?
    else
      return [SchemaValidationError.new(property_name, "Property '#{property_name}' values must be strings")] unless value.is_a?(String)
    end

    []
  end

  # This is a specialized version of validate_value_type for system properties only.
  sig { params(property_name: String, value_type: String, value: PropertyValue).returns(T::Array[SchemaValidationError]) }
  def validate_system_value_type(property_name, value_type, value)
    case value_type
    when "multi_select"
      return [SchemaValidationError.new(property_name, "Property '#{property_name}' value must be a list of strings")] unless value.is_a?(Array)

      has_duplicate_values = value.uniq.length != value.length
      return [SchemaValidationError.new(property_name, "Property '#{property_name}' values must be distinct")] if has_duplicate_values
    when "url"
      return [SchemaValidationError.new(property_name, "Property '#{property_name}' value must be a single url")] unless value.is_a?(String)

      err = invalid_url?(value)
      return [SchemaValidationError.new(property_name, err)] if err
    else
      return [SchemaValidationError.new(property_name, "Property '#{property_name}' value must be a single string")] unless value.is_a?(String)
    end

    []
  end

  # We don't type value as PropertyValue here because we want to allow invalid types to be passed in so that we can return the appropriate error messages.
  sig { params(property_name: String, value: T.untyped, max_value_length: Integer).returns(T::Array[SchemaValidationError]) }
  def validate_single_value(property_name, value, max_value_length:)
    errors = []

    case value
    when String
      unless value.size <= max_value_length
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

  # Actors are stored in the format "type|id"; for example, "user|234". "|" is not a valid character in values, so
  # it's a safe delimiter. This is only used to validate that the final value making it into the DB is valid, and that
  # the provided actor is valid for the definition's org/enterprise. Callers that set values (such as the API and the UI)
  # must perform their own validations and transform the user-provided values into this final DB value.
  sig { params(value: T.nilable(PropertyValue), source: IPropertySource).returns(T.nilable(String)) }
  def invalid_actor?(value, source)
    return "Actor is missing" unless value && value.is_a?(String)

    # ensure the format is "valid_type|actual_integer"
    split = value.split("|")
    return "Invalid actor format" unless split.size == 2

    type, id_str = split
    return "Invalid actor type" unless VALID_ACTOR_TYPES.include?(type)
    return "Invalid actor ID" unless id = Integer(id_str) rescue nil

    # ensure the actor can be selected for the definition's org/enterprise
    case type
    when "user"
      user = User.find_by(id: id)
      return "User not found" unless user

      source_to_check = if source.is_a?(Orgs::IOrganization)
        source.business || source
      else
        source
      end

      source_label = source_to_check.is_a?(Orgs::IOrganization) ? "organization" : "enterprise"
      "User is not a member of the #{source_to_check.safe_profile_name} #{source_label}" unless source_to_check.member?(user)
    end
  end

  sig { returns(Regex::RE2Helper) }
  memoize def regex_validator
    Regex::RE2Helper.new
  end
end
