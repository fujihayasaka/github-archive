# frozen_string_literal: true

class AllowedUpdatesValidator < ActiveModel::EachValidator
  KEYS = %i(dependency_name update_type dependency_type update_types).freeze
  UPDATE_TYPES = %w(security all).freeze
  DEPENDENCY_TYPES = %w(production development direct indirect all).freeze
  SEMVER_UPDATE_TYPES = %w(
    version-update:semver-major
    version-update:semver-minor
    version-update:semver-patch
  ).freeze

  def validate_each(record, attribute, value)
    return unless value

    unless value.is_a?(Array)
      record.errors.add(attribute, "must be an array of hashes")
      return
    end

    if value.empty?
      record.errors.add(attribute, "must be an array of hashes")
      return
    end

    value.each do |update|
      validate_allowed_update(update, record, attribute)
    end
  end

  private

  def validate_allowed_update(update, record, attribute)
    return record.errors.add(attribute, "must be an array of hashes") unless update.is_a?(Hash)

    symbolized = update.symbolize_keys
    check_allowed_update_keys(update, record, attribute)
    check_update_type(symbolized, record, attribute)
    check_dependency_type(symbolized, record, attribute)
    check_dependency_name(symbolized, record, attribute)
    check_update_types(symbolized, record, attribute)
  end

  def check_allowed_update_keys(update, record, attribute)
    unless (update.keys.map(&:to_sym) - KEYS).empty?
      msg = "contains an unrecognized condition: #{update}"
      return record.errors.add(attribute, msg)
    end

    return if update.keys.any?

    record.errors.add(attribute, "contains an empty hash")
  end

  def check_update_type(update, record, attribute)
    return unless update.key?(:update_type)

    update_type = update.fetch(:update_type)
    return if UPDATE_TYPES.include?(update_type)

    msg = "contains an unrecognized update_type: #{update_type}"
    record.errors.add(attribute, msg)
  end

  def check_dependency_type(update, record, attribute)
    return unless update.key?(:dependency_type)

    dependency_type = update.fetch(:dependency_type)
    return if DEPENDENCY_TYPES.include?(dependency_type)

    msg = "contains an unrecognized dependency_type: #{dependency_type}"
    record.errors.add(attribute, msg)
  end

  def check_dependency_name(update, record, attribute)
    return unless update.key?(:dependency_name)
    return if update.fetch(:dependency_name).is_a?(String)

    record.errors.add(attribute, "dependency_name must be a string")
  end

  def check_update_types(update, record, attribute)
    return unless update.key?(:update_types)

    update_types = update.fetch(:update_types)

    unless update_types.is_a?(Array)
      record.errors.add(attribute, "update_types must be an array of semver update-type strings")
      return
    end

    if update_types.length > SEMVER_UPDATE_TYPES.length
      record.errors.add(attribute, "update_types can contain at most #{SEMVER_UPDATE_TYPES.length} items")
      return
    end

    error = update_types_error(update_types)
    record.errors.add(attribute, error) if error
  end

  def update_types_error(update_types)
    return "contains unrecognized update_types value(s): empty array" if update_types.empty?

    invalid_values = update_types.reject { |t| t.is_a?(String) && SEMVER_UPDATE_TYPES.include?(t) }
    "contains unrecognized update_types value(s): #{invalid_values}" if invalid_values.any?
  end
end
