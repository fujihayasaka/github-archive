# typed: true
# frozen_string_literal: true

module UI
  class Validator
    attr_reader :schema, :errors, :deprecation_warnings
    def initialize(schema)

      @schema = case
      when schema.is_a?(Hash)
        schema.deep_stringify_keys
      else
        schema
      end

      @errors = ActiveModel::Errors.new(self)
      @deprecation_warnings = ActiveModel::Errors.new(self)
    end

    def validate!
      raise NotImplementedError, "Must implement validate!"
    end

    # Determines if the schema is valid
    #
    # It is safe to run this method multiple times
    #
    # @returns <Boolean> a boolean representing if there were errors found during validation
    #
    def valid?
      return @valid if defined? @valid
      @valid = begin
        validate!
        errors.empty?
      end
    end

    private

    def validate_type(base_key, expected_key, value, type)
      if value.nil?
        errors.add(backtick(base_key), "was expected to have the key #{backtick(expected_key)}")
        false
      elsif value.is_a?(type)
        true
      else
        errors.add(
          backtick(expected_key),
          "was expected to be a #{backtick(type.name)} but it was a #{backtick(value.class.name)}"
        )
        false
      end
    end

    # Validate that a value is a string and has a maximum length
    #
    # @param val <Object> value to validate being a string
    # @param path <String> the path inside of the schema, used to form error messages
    # @param length <Integer> the max length val should be
    #
    def validate_string_of_length(val:, path:, length:)
      if !val.is_a?(String)
        errors.add(backtick(path), "must be a `String`")
      elsif val.length > length
        errors.add(backtick(path), "must be at most #{backtick(length)} characters long, but was #{backtick(val.length)}")
      end
    end

    # Validate expected and missing keys for a given entry
    #
    # @param key [String] the key under which an error should be added
    # @param expected_keys <Array<String>> a list of expected keys
    # @param actual_keys <Array<String>> a list of actual keys
    # @param optional: <Array<String>> a list of optional keys
    #
    # @returns should_continue <Boolean> a boolean representing if the caller should continue (true) or return (false)
    #
    def validate_expected_keys(key, expected_keys, actual_keys, optional: [])
      allowed_keys = expected_keys + optional
      should_continue = true

      return should_continue if expected_keys.empty?

      if (missing_keys = expected_keys - actual_keys).present?
        missing_keys_sentence = missing_keys
          .map { |key| backtick(key) }
          .to_sentence
        errors.add(
          backtick(key),
          "was expected to include the #{"key".pluralize(missing_keys.length)} #{missing_keys_sentence}"
        )
        should_continue = false
      end

      if (extra_keys = actual_keys - allowed_keys).present?
        extra_keys_scentence = extra_keys
          .map { |key| backtick(key) }
          .to_sentence(last_word_connector: ", or ", two_words_connector: " or ")
        errors.add(
          backtick(key),
          "was not expected to include the #{"key".pluralize(extra_keys.length)} #{extra_keys_scentence}"
        )
      end

      should_continue
    end

    # Validates the inclusion of a value in a list of allowed values
    #
    # @param key <String> the key under which an error should be added
    # @param label <String> optional sub-key under which an error should be added. Concatenated with key.
    # @param values <Array<String>> a list of given values
    # @param allowed_values <Array<String>> a list of values against which values will be validated
    #
    def validate_inclusion(key:, label: "", values:, allowed_values:)
      invalid_values = values - allowed_values
      if invalid_values.present?
        sentenced_invalid_values = invalid_values
          .map { |key| backtick(key) }
          .to_sentence
        sentenced_allowed_values = allowed_values
          .map { |key| backtick(key) }
          .to_sentence(last_word_connector: ", or ", two_words_connector: " or ")
        errors.add(
          backtick("#{key}#{label}"),
          "#{sentenced_invalid_values} must be one of #{sentenced_allowed_values}"
        )
      end
    end

    # Validates the maximum size of a collection
    #
    # @param target <String> the key under which an error should be added
    # @param label <String> the name of one of the objects being validated. Used for the error message. e.g. "step" or "field"
    # @param size <Integer> the actual size of the collection
    # @param limit <Integer> the maximum size allowed
    #
    def validate_max_size(target:, label:, size:, limit:)
      if size > limit
        delta = size - limit
        errors.add(
          backtick(target),
          "is currently limited to #{backtick(limit)}#{" #{label.pluralize(limit)}".rstrip}, but you currently have #{backtick(size)}. Please remove at least #{backtick(delta)}#{" #{label.pluralize(delta)}".rstrip}."
        )
      end
    end

    # Adds a deprecation warning for a given field. If the feature flag given is enabled, the deprecation warning becomes an error.
    #
    # @param field <String> the field to be deprecated. Please pass this string in without surrounding it in backticks.
    # @param use_instead: <String> the field to use instead of the deprecated field. Please pass this string in without surrounding it in backticks.
    # @param code_block: <String> a code block included in the warning/error displaying how to fix. This code block will be rendered in our markdown pipeline.
    # @param date: <Date> the date which the deprecation warning will become an error. This field is for display purposes only, and does not actually deprecate the field. Please see the param `feature_flag` for that.
    # @param feature_flag: <Symbol> a symbol reflecting a feature flag. When the feature flag is enabled the deprecation warning becomes an error.
    #
    def deprecate(field, use_instead:, code_block:, date: nil, feature_flag: nil)
      message = if use_instead.present?
        "is deprecated. Please use `#{use_instead}` instead"
      else
        "is deprecated. Please remove all usage of it"
      end

      if code_block.present?
        message += ":\n" + code_block.indent(2)
      end

      if date.present?
        message += "\n" unless code_block.present?
        message += "<i>Deprecation in effect on **#{date}**</i>".indent(2)
      end

      if feature_flag.present? && GitHub.flipper[feature_flag].enabled?
        errors.add(backtick(field), message)
      else
        deprecation_warnings.add(backtick(field), message)
      end
    end

    # Adds a deprecation warning for a given field's value. If the feature flag given is enabled, the deprecation warning becomes an error.
    #
    # @param field <String> the field where the deprecated value is located. Please pass this string in without surrounding it in backticks.
    # @param value <String> the value to be deprecated. Please pass this string in without surrounding it in backticks.
    # @param new_field: <String> the field to use instead of the deprecated field. Please pass this string in without surrounding it in backticks.
    # @param new_value: <String> the value to use instead of the deprecated value. Please pass this string in without surrounding it in backticks.
    # @param code_block: <String> a code block included in the warning/error displaying how to fix. This code block will be rendered in our markdown pipeline.
    # @param date: <Date> the date which the deprecation warning will become an error. This field is for display purposes only, and does not actually deprecate the field. Please see the param `feature_flag` for that.
    # @param feature_flag: <Symbol> a symbol reflecting a feature flag. When the feature flag is enabled the deprecation warning becomes an error.
    #
    def deprecate_value(field, value, new_field:, new_value:, code_block:, date: nil, feature_flag: nil)
      deprecate(
        "#{field}:#{value}",
        use_instead: "#{new_field}:#{new_value}",
        code_block: code_block,
        date: date,
        feature_flag: feature_flag
      )
    end

    def backtick(str)
      "`#{str}`"
    end

    # ActiveModel Error minimal API requirements

    # rubocop:disable Lint/IneffectiveAccessModifier
    def read_attribute_for_validation(attr)
      send(attr)
    end

    def self.human_attribute_name(attr, options = {})
      attr
    end

    def self.lookup_ancestors
      [self]
    end
    # rubocop:enable Lint/IneffectiveAccessModifier
  end
end
