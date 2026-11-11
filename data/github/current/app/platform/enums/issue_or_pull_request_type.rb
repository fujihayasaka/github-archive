# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class IssueOrPullRequestType < Platform::Enums::Base
      description "Types of objects a user can filter a list of pull requests and issues by."

      visibility :under_development

      value "ISSUE", "Filter list to just issues.", value: "issue"
      value "PULL_REQUEST", "Filter list to just pull requests.", value: "pr"
    end
  end
end
