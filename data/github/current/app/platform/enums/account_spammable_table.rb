# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class AccountSpammableTable < Platform::Enums::Base
      description "A table with data that belongs to an account and can be used for spam or abuse."
      visibility :internal

      value "ABUSE_REPORT", "An abuse report", value: "abuse_reports"
      value "COMMIT_COMMENT_REACTION", "A reaction on a commit comment", value: "commit_comment_reactions"
      value "COMMIT_COMMENT", "A comment on a commit", value: "commit_comments"
      value "CROSS_REFERENCE", "A cross reference", value: "cross_references"
      value "DISCUSSION_COMMENT_REACTION", "A reaction on a discussion comment", value: "discussion_comment_reactions"
      value "DISCUSSION_COMMENT", "A comment on a discussion", value: "discussion_comments"
      value "DISCUSSION_REACTION", "A reaction on a discussion", value: "discussion_reactions"
      value "DISCUSSION", "A discussion", value: "discussions"
      value "FOLLOWER", "A follower", value: "followers"
      value "GIST_COMMENT", "A comment on a gist", value: "gist_comments"
      value "GIST", "A gist", value: "gists"
      value "INTEGRATION", "An integration", value: "integrations"
      value "ISSUE_COMMENT_REACTION", "A reaction on an issue comment", value: "issue_comment_reactions"
      value "ISSUE_COMMENT", "A comment on an issue", value: "issue_comments"
      value "ISSUE_EVENT_AUTHOR", "An author of an issue event", value: "issue_event_authors"
      value "ISSUE_REACTION", "A reaction on an issue", value: "issue_reactions"
      value "ISSUE", "An issue", value: "issues"
      value "MEMEX_PROJECT_ITEM", "An item in a project", value: "memex_project_items"
      value "MEMEX_PROJECT_STATUS", "A status in a project", value: "memex_project_statuses"
      value "MEMEX_PROJECT", "A project", value: "memex_projects"
      value "MILESTONE", "A milestone", value: "milestones"
      value "OAUTH_APPLICATION", "An OAuth application", value: "oauth_applications"
      value "PROFILE", "A user profile", value: "profiles"
      value "PULL_REQUEST_REVIEW_COMMENT_REACTION", "A reaction on a pull request review comment", value: "pull_request_review_comment_reactions"
      value "PULL_REQUEST_REVIEW_COMMENT", "A comment on a pull request review", value: "pull_request_review_comments"
      value "PULL_REQUEST_REVIEW_REACTION", "A reaction on a pull request review", value: "pull_request_review_reactions"
      value "PULL_REQUEST_REVIEW", "A pull request review", value: "pull_request_reviews"
      value "PULL_REQUEST", "A pull request", value: "pull_requests"
      value "REACTION", "A reaction on a piece of content", value: "reactions"
      value "REPOSITORY", "A repository", value: "repositories"
      value "STAR", "A star on a piece of content", value: "stars"
      value "USER_EMAIL", "An email address", value: "user_emails"
      value "WORKFLOW_RUN", "A workflow run", value: "workflow_runs"
    end
  end
end
