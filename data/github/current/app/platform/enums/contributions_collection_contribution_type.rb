# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ContributionsCollectionContributionType < Platform::Enums::Base
      description "Different ways a user can contribute on GitHub."
      visibility :under_development

      value "CREATED_COMMIT", "Created a commit", value: Contribution::CreatedCommit
      value "CREATED_ISSUE", "Created an issue", value: Contribution::CreatedIssue
      value "CREATED_PULL_REQUEST", "Created a pull request", value: Contribution::CreatedPullRequest
      value "CREATED_COMMENT", "Created a comment on an issue or pull request", value: Contribution::CreatedIssueComment
      value "CREATED_REPOSITORY", "Created a repository", value: Contribution::CreatedRepository
      value "CREATED_PULL_REQUEST_REVIEW", "Reviewed a pull request", value: Contribution::CreatedPullRequestReview
      value "JOINED_ORGANIZATION", "Became a member of an organization", value: Contribution::JoinedOrganization
      value "JOINED_GITHUB", "Signed up for GitHub", value: Contribution::JoinedGitHub
      value "GITHUB_ENTERPRISE", "Contributions reported from a GitHub Enterprise installation", value: Contribution::EnterpriseContributionInfo
      value "ANSWERED_DISCUSSION", "Answered a discussion", value: Contribution::AnsweredDiscussion
      value "CREATED_DISCUSSION", "Created a discussion", value: Contribution::CreatedDiscussion
    end
  end
end
