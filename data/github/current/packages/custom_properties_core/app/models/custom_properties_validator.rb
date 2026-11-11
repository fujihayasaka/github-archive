# typed: strict
# frozen_string_literal: true

module CustomPropertiesValidator
  extend self

  include Kernel

  include CustomPropertiesCore
  include CustomPropertiesCore::Errors
  include GitHub::Memoizer

  VALID_ACTOR_TYPES = %w[user]
  private_constant :VALID_ACTOR_TYPES

  MAX_SYSTEM_PROPERTY_VALUE_LENGTH = 200
  private_constant :MAX_SYSTEM_PROPERTY_VALUE_LENGTH

  MAX_EXTERNAL_PROPERTY_VALUE_LENGTH = 200
  private_constant :MAX_EXTERNAL_PROPERTY_VALUE_LENGTH

  sig do
    params(
      definitions: T::Array[IPropertyDefinition],
      properties: T::Hash[String, T.nilable(PropertyValue)],
      limits: PropertyLimits,
    ).returns(T::Array[SchemaValidationError])
  end
  def validate_properties(definitions, properties, limits:)
    definitions_hash = T.let(definitions.index_by(&:property_name).transform_keys(&:downcase), T::Hash[String, IPropertyDefinition])
    errors = validate_schema(definitions_hash, properties)

    if errors.empty?
      # At this point we can be sure that all property names are valid
      properties_with_definitions = properties.to_h { |name, value| [T.must(definitions_hash[name.downcase]), value] }
      errors += validate_values(properties_with_definitions, limits)
    end

    errors.uniq { |e| e.error_message }
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

  # Returns a validation error for a definition's +value_type+ attribute, or nil if valid.
  # Pass +actor_type_enabled: true+ when the "actor" value type has been enabled for the context.
  # Assumes that the presence of +value_type+ has already been validated.
  sig do
    params(
      definition: IPropertyDefinition,
      actor_type_enabled: T::Boolean,
    ).returns(T.nilable(DefinitionValidationError))
  end
  def validate_definition_value_type(definition:, actor_type_enabled: false)
    supported_types = %w[string single_select true_false multi_select url]
    supported_types << "actor" if actor_type_enabled

    return nil if supported_types.include?(definition.value_type)

    DefinitionValidationError.new(:value_type, "has unsupported value '#{definition.value_type}'")
  end

  # Returns a validation error for a definition's +regex+ attribute, or nil if valid.
  # Assumes that the presence of +value_type+ has already been validated.
  sig do
    params(
      definition: IPropertyDefinition,
    ).returns(T.nilable(DefinitionValidationError))
  end
  def validate_definition_regex(definition:)
    return nil unless definition.regex

    if definition.value_type == "string"
      regex_validator.is_valid?(T.must(definition.regex)) ? nil : DefinitionValidationError.new(:regex, "must be a valid regex pattern")
    else
      DefinitionValidationError.new(:regex, "is only supported on string properties")
    end
  end

  # Returns a validation error for a definition's +allowed_values+ attribute, or nil if valid.
  # Assumes that the presence of +value_type+ has already been validated.
  # This method will remove type information from the allowed_values array in order to validate that each element is a string
  sig do
    params(
      definition: IPropertyDefinition,
      limits: PropertyLimits,
    ).returns(T.nilable(DefinitionValidationError))
  end
  def validate_definition_allowed_values(definition:, limits:)
    # We haven't validated the contents of allowed_values yet, so we need to T.unsafe here to untype it.
    allowed_values = T.unsafe(definition.allowed_values)
    value_type = definition.value_type

    if value_type == "single_select" || value_type == "multi_select"
      return DefinitionValidationError.new(:allowed_values, "must be present for value_type #{value_type}") if allowed_values.nil?
      return DefinitionValidationError.new(:allowed_values, "must be an array of strings for value_type #{value_type}") unless allowed_values.is_a?(Array)
      return DefinitionValidationError.new(:allowed_values, "must contain at least one value for value_type #{value_type}") if allowed_values.empty?

      max_count = limits.max_allowed_values_count
      return DefinitionValidationError.new(:allowed_values, "must be maximum #{max_count} values") if allowed_values.size > max_count

      max_len = limits.max_property_value_length
      allowed_values.uniq.each do |value|
        return DefinitionValidationError.new(:allowed_values, "'#{value}' must be a string") unless value.is_a?(String)
        return DefinitionValidationError.new(:allowed_values, "'#{value}' must be at most #{max_len} characters") unless value.length <= max_len

        invalid_chars = value_invalid_chars(value)
        return DefinitionValidationError.new(:allowed_values, "'#{value}' contains invalid characters: #{invalid_chars}") unless invalid_chars.empty?
      end

      counts = T.let({}, T::Hash[T.untyped, T::Array[T.untyped]])
      allowed_values.each do |value|
        normalized = value.is_a?(String) ? value.strip.downcase : value
        counts[normalized] ||= []
        T.must(counts[normalized]) << value
      end
      dupes = counts.filter { |_, v| v.count > 1 }.values.map { |arr| arr.first }
      return DefinitionValidationError.new(:allowed_values, "contains duplicates: #{dupes.join(", ")}") if dupes.any?

      nil
    else
      allowed_values.nil? ? nil : DefinitionValidationError.new(:allowed_values, "must be nil if value_type is #{value_type}")
    end
  end

  # Returns a validation error for a definition's +default_value+ attribute, or nil if valid.
  # Assumes that the presence of +value_type+ has already been validated.
  sig do
    params(
      definition: IPropertyDefinition,
      limits: PropertyLimits,
    ).returns(T.nilable(DefinitionValidationError))
  end
  def validate_definition_default_value(definition:, limits:)
    required = definition.required
    value_type = definition.value_type
    default_value = definition.default_value
    allowed_values = definition.allowed_values
    regex = definition.regex

    if required
      return DefinitionValidationError.new(:default_value, "must be present") if default_value.blank?

      dv = default_value

      if value_type == "multi_select"
        is_valid = dv.is_a?(Array) && Array(dv).all? { |v| v.is_a?(String) }
        return DefinitionValidationError.new(:default_value, "must be an array of strings for 'multi_select' property") unless is_valid
      else
        return DefinitionValidationError.new(:default_value, "must be a string for '#{value_type}' property") unless dv.is_a?(String)
      end

      case value_type
      when "string"
        dv_str = T.cast(dv, String)
        max_len = limits.max_property_value_length_by_type(value_type)
        return DefinitionValidationError.new(:default_value, "must be at most #{max_len} characters") if dv_str.length > max_len

        invalid_chars = value_invalid_chars(dv_str)
        return DefinitionValidationError.new(:default_value, "contains invalid characters: #{invalid_chars}") if invalid_chars.present?

        return DefinitionValidationError.new(:default_value, "must match regular expression #{regex}") if regex && !regex_validator.matches?(dv_str, regex)
      when "single_select", "multi_select"
        invalid_values = Array(dv) - Array(allowed_values)
        return DefinitionValidationError.new(:default_value, "must be part of the allowed values") if invalid_values.present?
      when "true_false"
        dv_str = T.cast(dv, String)
        return DefinitionValidationError.new(:default_value, "must be 'true' or 'false'") unless %w[true false].include?(dv_str)
      when "url"
        dv_str = T.cast(dv, String)
        max_len = limits.max_property_value_length_by_type(value_type)
        return DefinitionValidationError.new(:default_value, "must be at most #{max_len} characters") if dv_str.length > max_len

        url_err = invalid_url?(dv_str)
        return DefinitionValidationError.new(:default_value, url_err) if url_err
      when "actor"
        # No additional validation for actor type at the moment
      else
        raise ArgumentError, "Default value validation is not configured for '#{value_type}' property type"
      end

      nil
    else
      default_value.present? ? DefinitionValidationError.new(:default_value, "must be empty") : nil
    end
  end

  # Common limits object for system properties
  sig { returns(PropertyLimits) }
  memoize def system_property_limits
    PropertyLimits.new(max_property_value_length: MAX_SYSTEM_PROPERTY_VALUE_LENGTH)
  end

  # Common limits object for external properties
  sig { returns(PropertyLimits) }
  memoize def external_property_limits
    PropertyLimits.new(max_property_value_length: MAX_EXTERNAL_PROPERTY_VALUE_LENGTH)
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
