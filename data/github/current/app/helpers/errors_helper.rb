# typed: true
# frozen_string_literal: true

module ErrorsHelper
  def field_has_errors?(record, field)
    record && record.errors[field].any?
  end

  def errors_sentence_for(record, field, human_field: nil)
    return false if !field_has_errors?(record, field)
    "#{human_field || record.class.human_attribute_name(field)} #{record.errors[field].to_sentence}"
  end

  # Returns a single error String
  def error_for(record, field, human_field: nil)
    return false if !field_has_errors?(record, field)
    "#{human_field || record.class.human_attribute_name(field)} #{record.errors[field].first}"
  end
end
