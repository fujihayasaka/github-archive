# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryContributionType < Platform::Enums::Base
      description "The reason a repository is listed as 'contributed'."

      value "COMMIT", "Created a commit", value: Contribution::CreatedCommit
      value "ISSUE", "Created an issue", value: Contribution::CreatedIssue
      value "PULL_REQUEST", "Created a pull request", value: Contribution::CreatedPullRequest
      value "REPOSITORY", "Created the repository", value: Contribution::CreatedRepository
      value "PULL_REQUEST_REVIEW", "Reviewed a pull request", value: Contribution::CreatedPullRequestReview
    end
  end
end
