# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PinnableItemType < Platform::Enums::Base
      description "Represents items that can be pinned to a profile page or dashboard."

      value "REPOSITORY", "A repository.", value: "Repository"
      value "GIST", "A gist.", value: "Gist"
      value "ISSUE", "An issue.", value: "Issue"
      value "PROJECT", "A project.", value: "Project"
      value "PULL_REQUEST", "A pull request.", value: "PullRequest"
      value "USER", "A user.", value: "User"
      value "ORGANIZATION", "An organization.", value: "Organization"
      value "TEAM", "A team.", value: "Team"
    end
  end
end
