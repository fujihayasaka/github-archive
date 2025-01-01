# typed: strict
# frozen_string_literal: true

module Platform
  module Unions
    class IssueFieldValue < Platform::Unions::Base
      description "Issue field values"

      visibility :under_development

      possible_types(
        Objects::IssueFieldTextValue,
        Objects::IssueFieldSingleSelectValue,
      )
    end
  end
end
