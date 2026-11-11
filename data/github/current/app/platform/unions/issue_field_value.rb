# typed: strict
# frozen_string_literal: true

module Platform
  module Unions
    class IssueFieldValue < Platform::Unions::Base
      docs_category :issues
      description "Issue field values"

      possible_types(
        Objects::IssueFieldTextValue,
        Objects::IssueFieldSingleSelectValue,
        Objects::IssueFieldMultiSelectValue,
        Objects::IssueFieldDateValue,
        Objects::IssueFieldNumberValue
      )
    end
  end
end
