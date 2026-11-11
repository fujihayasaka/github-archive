# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectV2FieldType < Platform::Enums::Base
      description "The type of a project field."

      value "ASSIGNEES", "Assignees", value: "assignees"
      value "LINKED_PULL_REQUESTS", "Linked Pull Requests", value: "linked_pull_requests"
      value "REVIEWERS", "Reviewers", value: "reviewers"
      value "LABELS", "Labels", value: "labels"
      value "MILESTONE", "Milestone", value: "milestone"
      value "REPOSITORY", "Repository", value: "repository"
      value "TITLE", "Title", value: "title"
      value "TEXT", "Text", value: "text"
      value "SINGLE_SELECT", "Single Select", value: "single_select"
      value "NUMBER", "Number", value: "number"
      value "DATE", "Date", value: "date"
      value "ITERATION", "Iteration", value: "iteration"
      value "TRACKS", "Tracks", value: "tracks"
      value "TRACKED_BY", "Tracked by", value: "tracked_by"
      # See https://github.com/github/issues/issues/7573 for more information about issue types in projects.
      value "ISSUE_TYPE", "Issue type", value: "issue_type"
      value "PARENT_ISSUE", "Parent issue", value: "parent_issue"
      value "SUB_ISSUES_PROGRESS", "Sub-issues progress", value: "sub_issues_progress"
    end
  end
end
