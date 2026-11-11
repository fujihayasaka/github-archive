# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class ProjectV2IssueFieldValues < Platform::Unions::Base
      docs_category :projects
      description "Possible issue field values for a Project item."

      possible_types(
        Objects::IssueFieldTextValue,
        Objects::IssueFieldNumberValue,
        Objects::IssueFieldDateValue,
        Objects::IssueFieldSingleSelectValue,
        Objects::IssueFieldMultiSelectValue,
      )
    end
  end
end
