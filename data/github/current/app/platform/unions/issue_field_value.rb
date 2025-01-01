# typed: strict
# frozen_string_literal: true

module Platform
  module Unions
    class IssueFieldValue < Platform::Unions::Base
      description "Issue field values"
      feature_flag :issue_fields

      possible_types(
        Objects::IssueFieldTextValue,
        Objects::IssueFieldSingleSelectValue,
        Objects::IssueFieldDateValue,
        Objects::IssueFieldNumberValue
      )
    end
  end
end
