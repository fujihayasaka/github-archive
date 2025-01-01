# typed: true
# frozen_string_literal: true

module MemexProjectColumn::ConversionDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  extend T::Sig

  requires_ancestor { MemexProjectColumn }

  ALLOWED_DATA_TYPE_CONVERSIONS = {
    single_select: [:text],
    text: [:single_select],
  }.freeze

  attr_accessor :skip_data_type_converting_check

  sig { returns(T.nilable(String)) }
  def data_type_conversion_key
    return unless persisted?
    "memex-project-column:#{id}:data-type-conversion"
  end

  sig { params(new_data_type: T.any(String, Symbol)).returns(T::Boolean) }
  def mark_as_changing_data_type(new_data_type)
    return false unless persisted? && new_data_type.to_s.present?
    # rubocop:todo GitHub/DoNotUseGlobalKv
    GitHub.kv.set(data_type_conversion_key, new_data_type.to_s, expires: 1.day.from_now)
    # rubocop:enable GitHub/DoNotUseGlobalKv
    self.skip_data_type_converting_check = true
  end

  sig { void }
  def mark_as_data_type_change_finished
    return if new_record?
    self.skip_data_type_converting_check = false
    GitHub.kv.del(data_type_conversion_key) # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  sig { returns(T::Boolean) }
  def changing_data_type?
    return false unless persisted?
    GitHub.kv.exists(data_type_conversion_key).value! # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  private

  def data_type_conversion_is_allowed
    return unless data_type_was

    key = T.must(data_type_was).to_sym
    unless ALLOWED_DATA_TYPE_CONVERSIONS.key?(key)
      errors.add(:data_type, "cannot be changed")
      return
    end

    unless ALLOWED_DATA_TYPE_CONVERSIONS[key].include?(data_type.to_sym)
      errors.add(:data_type, "cannot be changed to #{data_type.to_s.humanize.downcase}")
    end

    if !skip_data_type_converting_check && changing_data_type?
      errors.add(:data_type, "is already being changed")
    end
  end
end
