# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class MarkdownPreviewSubjectType < Platform::Enums::Base
      description "The subject type to be used when generating a markdown preview"
      mobile_only true

      value "ISSUE", "Generates a markdown preview for a new issue body", value: "Issue"
      value "PULL", "Generates a markdown preview for a new pull request body", value: "PullRequest"
      value "DISCUSSION", "Generates a markdown preview for a new discussion body", value: "Discussion"
    end
  end
end
