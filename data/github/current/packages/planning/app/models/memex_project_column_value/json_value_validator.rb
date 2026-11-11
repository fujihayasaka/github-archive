# typed: true
# frozen_string_literal: true

class MemexProjectColumnValue::JsonValueValidator < ActiveModel::Validator

  ISSUE_TITLE_REQUIRED_KEYS = %w(number state issueId url)
  PULL_REQUEST_TITLE_REQUIRED_KEYS = ISSUE_TITLE_REQUIRED_KEYS + %w(isDraft)
  MILESTONE_REQUIRED_KEYS = %w(id number state title url)

  def validate(record)
    return unless record.title? || record.milestone? || record.generic_type?

    unless record.json_value&.is_a?(Hash)
      record.errors.add(:json_value, "must be a Hash")
      return
    end

    case record.data_type.to_sym
    when :title
      validate_formatted_title_data(record)
    when :milestone
      validate_formatted_milestone_data(record)
    when :text
      validate_formatted_text_data(record)
    when :single_select
      validate_formatted_single_select_data(record)
    when :date
      validate_formatted_date_data(record)
    when :number
      validate_formatted_number_data(record)
    end

  end

  def validate_formatted_title_data(record)
    # We use `blank?` throughout this method to reject empty strings as well as `nil` values.
    if record.json_value["title"].blank?
      record.errors.add(:json_value, "must include a 'title' value")
      return
    end

    title_object = record.json_value["title"]
    if title_object["raw"].blank?
      record.errors.add(:json_value, "'title' object must include a 'raw' value")
    end

    if title_object["html"].blank?
      record.errors.add(:json_value, "'title' object must include an 'html' value")
    end

    case record.memex_project_item.content_type
    when "Issue"
      validate_content_specific_title_data(record, ISSUE_TITLE_REQUIRED_KEYS)
    when "PullRequest"
      validate_content_specific_title_data(record, PULL_REQUEST_TITLE_REQUIRED_KEYS)
    end
  end

  def validate_content_specific_title_data(record, required_keys)
    required_keys.each do |key|
      # These values might be booleans (and therefore `false`), so use `nil?` rather than `blank?`
      if record.json_value[key].nil?
        record.errors.add(
          :json_value,
          "#{record.memex_project_item.content_type} 'title' object must include '#{key}' value"
        )
      end
    end
  end

  def validate_formatted_milestone_data(record)
    if record.json_value["type"] != "Milestone"
      record.errors.add(:json_value, "must include a 'type' of 'Milestone'")
      return
    end

    # We use `blank?` throughout this method to reject empty strings as well as `nil` values.
    if record.json_value["value"].blank?
      record.errors.add(:json_value, "must include a 'value' key")
      return
    end

    value_object = record.json_value["value"]

    MILESTONE_REQUIRED_KEYS.each do |key|
      if value_object[key].blank?
        record.errors.add(
          :json_value,
          "'milestone' object must include '#{key}' value"
        )
      end
    end
  end

  def validate_formatted_text_data(record)
    # We use `blank?` throughout this method to reject empty strings as well as `nil` values.
    # if the raw or html values are empty, then we should have deleted the column value instead of
    # saving it with an empty value
    if record.json_value["raw"].blank?
      record.errors.add(:json_value, "must include an entry for the 'raw' key")
    end

    if record.json_value["html"].blank?
      record.errors.add(:json_value, "must include an entry for the 'html' key")
    end
  end

  def validate_formatted_single_select_data(record)
    # We use `blank?` throughout this method to reject empty strings as well as `nil` values.
    if record.json_value["id"].blank?
      record.errors.add(:json_value, "must include an entry for the 'id' key")
    end
  end

  def validate_formatted_date_data(record)
    validate_json_value_has_value_key(record)
  end

  def validate_formatted_number_data(record)
    validate_json_value_has_value_key(record)
  end

  def validate_json_value_has_value_key(record)
    # We use `blank?` throughout this method to reject empty strings as well as `nil` values.
    if record.json_value["value"].blank?
      record.errors.add(:json_value,  "must include an entry for the 'value' key")
    end
  end
end
