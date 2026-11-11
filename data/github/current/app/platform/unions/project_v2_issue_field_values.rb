# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class ProjectV2IssueFieldValues < Platform::Unions::Base
      description "Possible issue field values for a Project item."

      feature_flag :issue_fields

      possible_types(
        Objects::IssueFieldTextValue,
        Objects::IssueFieldNumberValue,
        Objects::IssueFieldDateValue,
        Objects::IssueFieldSingleSelectValue,
      )
    end
  end
end
