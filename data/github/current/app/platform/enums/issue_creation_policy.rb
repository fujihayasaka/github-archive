# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class IssueCreationPolicy < Platform::Enums::Base
      docs_category :issues
      description "The policy controlling who can create issues in a repository."

      value "ALL", "Anyone can create issues.", value: Configurable::IssueCreationPolicy::ALL
      value "COLLABORATORS_ONLY", "Only collaborators can create issues.", value: Configurable::IssueCreationPolicy::COLLABORATORS_ONLY
    end
  end
end
