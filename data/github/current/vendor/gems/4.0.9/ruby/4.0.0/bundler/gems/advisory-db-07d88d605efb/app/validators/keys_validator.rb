# frozen_string_literal: true

class KeysValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return unless value.is_a?(Hash) # Hashiness should be validated separately

    expected_keys = Array(options[:contain] || options[:in])
    actual_keys = value.keys
    missing_keys = expected_keys - actual_keys

    return if missing_keys.empty?

    record.errors.add(attribute, :missing_keys, {
      expected_keys: expected_keys,
      actual_keys: actual_keys,
      missing_keys: missing_keys,
    })
  end
end
