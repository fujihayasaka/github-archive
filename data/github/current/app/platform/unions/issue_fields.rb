# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class IssueFields < Platform::Unions::Base
      description "Possible issue fields."
      visibility :under_development

      possible_types(
        Objects::IssueFieldText,
        Objects::IssueFieldSingleSelect,
      )
    end
  end
end
