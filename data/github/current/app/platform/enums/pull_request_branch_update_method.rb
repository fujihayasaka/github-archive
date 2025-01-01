# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestBranchUpdateMethod < Platform::Enums::Base
      description "The possible methods for updating a pull request's head branch with the base branch."

      value "MERGE", "Update branch via merge", value: "merge"
      value "REBASE", "Update branch via rebase", value: "rebase"
    end
  end
end
