# typed: strict
# frozen_string_literal: true

class IssueFieldDateValue < IssueFieldValue
  include Issues::IIssueFieldDateValue
  include GitHub::Memoizer

  validate :validate_raw_value_presence
  validate :validate_date_format

  sig { returns(String) }
  def self.sti_name
    "date"
  end

  sig { override.returns(Date) }
  def value
    if raw_value.blank?
      raise ArgumentError, "Date value can't be blank"
    end
    Date.parse(raw_value)
  end

  # Returns the ISO 8601 date string for ElasticSearch indexing
  sig { override.returns(T.nilable(String)) }
  def elasticsearch_value
    return nil unless raw_value.present?
    date_value = raw_value.is_a?(String) ? Date.parse(raw_value) : raw_value
    date_value.iso8601
  end

  sig { override.returns(T::Boolean) }
  def memex_column_value_present?
    raw_value.present?
  end

  sig { override.returns(MemexProjectColumnValue::Date) }
  memoize def memex_project_column_value
    MemexProjectColumnValue::Date.new(value: value.iso8601)
  end

  private

  sig { void }
  def validate_date_format
    return if raw_value.blank?

    begin
      Date.parse(raw_value)
    rescue ArgumentError
      errors.add(:value, "Must be a valid date format (YYYY-MM-DD)")
    end
  end
end
