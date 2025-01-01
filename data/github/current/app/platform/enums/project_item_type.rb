# typed: true
# frozen_string_literal: true

module Platform
  module Enums

    class ProjectItemType < Platform::Enums::Base
      description "The type of a project item."

      required_capabilities [:mobile_only_schema_mask]

      value "ISSUE", "Issue", value: "Issue"
      value "PULL_REQUEST", "Pull Request", value: "PullRequest"
      value "DRAFT_ISSUE", "Draft Issue", value: "DraftIssue"
      value "REDACTED", "Redacted Item", value: "RedactedItem"
    end
  end
end
