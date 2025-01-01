# typed: strict
# frozen_string_literal: true

module Platform
  module Unions
    class IssueFormElements < Platform::Unions::Base
      description "Issue form elements"

      possible_types(
        Objects::IssueFormElementInput,
        Objects::IssueFormElementMarkdown,
        Objects::IssueFormElementTextarea,
        Objects::IssueFormElementDropdown,
        Objects::IssueFormElementCheckboxes,
      )
    end
  end
end
