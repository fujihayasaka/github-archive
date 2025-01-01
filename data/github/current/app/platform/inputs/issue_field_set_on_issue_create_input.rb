# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class IssueFieldSetOnIssueCreateInput < Platform::Inputs::Base
      description "Represents an issue field value that must be set on an issue during issue creation"
      visibility :under_development

      argument :field_id, ID, "The ID of the issue field", required: true
      argument :text_value, String, "The text value, for a text field", required: false
      argument :single_select_option_id, ID, "The ID of the selected option, for a single select field", required: false
    end
  end
end
