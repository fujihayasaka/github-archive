# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PendingIssueSuggestionKind < Platform::Enums::Base
      docs_category :issues
      description "The kind of pending issue suggestion being applied."

      visibility :internal

      value "TYPE", "Set the issue's type to the suggested issue type.", value: "TYPE"
      value "LABEL", "Add the suggested label to the issue.", value: "LABEL"
      value "FIELD", "Set the suggested issue field value on the issue.", value: "FIELD"
    end
  end
end
