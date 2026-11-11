# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class IssueFieldCreateOrUpdateInput < Platform::Inputs::Base
      description "Represents an issue field value that must be set on an issue during issue creation"
      feature_flag :issue_fields

      argument :field_id, ID, "The ID of the issue field", required: true
      argument :text_value, String, "The text value, for a text field", required: false
      argument :date_value, String, "The date value, for a date field", required: false
      argument :single_select_option_id, ID, "The ID of the selected option, for a single select field", required: false
      argument :number_value, Float, "The numeric value, for a number field", required: false
      argument :delete, Boolean, "Set to true to delete the field value", required: false
    end
  end
end
