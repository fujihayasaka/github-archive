# frozen_string_literal: true

class AllowedUpdatesValidator < ActiveModel::EachValidator
  KEYS = %i(dependency_name update_type dependency_type).freeze
  UPDATE_TYPES = %w(security all).freeze
  DEPENDENCY_TYPES = %w(production development direct indirect all).freeze

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

    check_allowed_update_keys(update, record, attribute)
    check_update_type(update, record, attribute)
    check_dependency_type(update, record, attribute)
    check_dependency_name(update, record, attribute)
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
    return unless update.symbolize_keys.key?(:update_type)

    update_type = update.symbolize_keys.fetch(:update_type)
    return if UPDATE_TYPES.include?(update_type)

    msg = "contains an unrecognized update_type: #{update_type}"
    record.errors.add(attribute, msg)
  end

  def check_dependency_type(update, record, attribute)
    return unless update.symbolize_keys.key?(:dependency_type)

    dependency_type = update.symbolize_keys.fetch(:dependency_type)
    return if DEPENDENCY_TYPES.include?(dependency_type)

    msg = "contains an unrecognized dependency_type: #{dependency_type}"
    record.errors.add(attribute, msg)
  end

  def check_dependency_name(update, record, attribute)
    return unless update.symbolize_keys.key?(:dependency_name)
    return if update.symbolize_keys.fetch(:dependency_name).is_a?(String)

    record.errors.add(attribute, "dependency_name must be a string")
  end
end
