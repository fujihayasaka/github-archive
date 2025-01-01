# typed: strict
# frozen_string_literal: true

class IssueFieldSingleSelectValue < IssueFieldValue
  include Issues::IIssueFieldSingleSelectValue
  include MemexProjectColumn::IDataSource
  include GitHub::Memoizer

  validate :value_is_valid_for_single_select_field
  validate :single_select_value_is_present

  sig { returns(String) }
  def self.sti_name
    "single_select"
  end

  # Returns the IssueFieldOption object for the selected value, or nil
  sig { returns(T.nilable(IssueFieldOption)) }
  def option
    value_id = raw_value
    return nil if value_id.nil?
    return nil if issue_field_id.nil?

    T.must(issue_field).options.find { |option| option.id == value_id }
  end

  # Returns the name of the selected IssueFieldOption, or nil
  sig { override.returns(T.nilable(String)) }
  def value
    option&.name
  end

  # Returns the option ID as string for ElasticSearch indexing
  sig { override.returns(T.nilable(String)) }
  def elasticsearch_value
    return nil unless value.present?
    option&.id&.to_s
  end

  sig { override.returns(MemexProjectColumnValue::SingleSelect) }
  memoize def memex_project_column_value
    option = T.must(self.option)

    MemexProjectColumnValue::SingleSelect.new(
      id: option.id.to_s,
      name: option.name,
    )
  end

  private

  sig { void }
  def single_select_value_is_present
    if raw_value.nil? || raw_value.blank?
      errors.add(:value, "Single-select value can't be blank")
    end
  end

  sig { void }
  def value_is_valid_for_single_select_field
    return true if issue_field.nil?

    if data_type.nil?
      errors.add(:data_type, :invalid_data_type)
      return false
    end

    return true unless data_type.to_sym == :single_select
    return true if raw_value.nil?

    if data_type.nil?
      errors.add(:data_type, :invalid_data_type)
      return false
    end

    unless raw_value.is_a?(Integer)
      errors.add(:value, :must_be_a_valid_issue_field_option_id)
      return false
    end

    unless T.must(issue_field).options.any? { |option| option.id == raw_value }
      errors.add(:value, :must_be_a_valid_issue_field_option_id)
      false
    end
  end
end
