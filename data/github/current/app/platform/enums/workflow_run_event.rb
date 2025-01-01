# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    # The values in this enum should match the values in Repository::WorkflowsDependency::ALL_EVENTS.
    # Descriptions were taken from https://docs.github.com/actions/using-workflows/events-that-trigger-workflows
    class WorkflowRunEvent < Platform::Enums::Base
      description "List of all possible events that can trigger a workflow run"
      required_capabilities [:mobile_only_schema_mask]

      value "BRANCH_PROTECTION_RULE", "Triggered when branch protection rules in the workflow repository are changed.", value: "branch_protection_rule"
      value "CHECK_RUN", "Triggered when activity related to a check run occurs.", value: "check_run"
      value "CHECK_SUITE", "Triggered when check suite activity occurs.", value: "check_suite"
      value "CREATE", "Triggered when someone creates a Git reference (Git branch or tag) in the workflow's repository.", value: "create"
      value "DELETE", "Triggered when someone deletes a Git reference (Git branch or tag) in the workflow's repository.", value: "delete"
      value "DEPLOYMENT_STATUS", "Triggered when a third party provides a deployment status.", value: "deployment_status"
      value "DEPLOYMENT", "Triggered when someone creates a deployment in the workflow's repository.", value: "deployment"
      value "DISCUSSION_COMMENT", "Triggered when a comment on a discussion in the workflow's repository is created or modified.", value: "discussion_comment"
      value "DISCUSSION", "Triggered when a discussion in the workflow's repository is created or modified.", value: "discussion"
      value "DYNAMIC", "Triggered by an internal integration with another first-party feature.", value: "dynamic"
      value "FORK", "Triggered when someone forks a repository.", value: "fork"
      value "GOLLUM", "Triggered when someone creates or updates a Wiki page.", value: "gollum"
      value "ISSUE_COMMENT", "Triggered when an issue or pull request comment is created, edited, or deleted.", value: "issue_comment"
      value "ISSUES", "Triggered when an issue in the workflow's repository is created or modified", value: "issues"
      value "LABEL", "Triggered when a label in your workflow's repository is created or modified.", value: "label"
      value "MERGE_GROUP", "Triggered when a pull request is added to a merge queue, which adds the pull request to a merge group.", value: "merge_group"
      value "MILESTONE", "Triggered when a milestone in the workflow's repository is created or modified.", value: "milestone"
      value "PAGE_BUILD", "Triggered when someone pushes to a branch that is the publishing source for GitHub Pages, if GitHub Pages is enabled for the repository.", value: "page_build"
      value "PROJECT_CARD", "Triggered when a card on a project board is created or modified.", value: "project_card"
      value "PROJECT_COLUMN", "Triggered when a column on a project board is created or modified.", value: "project_column"
      value "PROJECT", "Triggered when a project board is created or modified.", value: "project"
      value "PUBLIC", "Triggered when your workflow's repository changes from private to public.", value: "public"
      value "PULL_REQUEST_REVIEW_COMMENT", "Triggered when a pull request review comment is modified.", value: "pull_request_review_comment"
      value "PULL_REQUEST_REVIEW", "Triggered when a pull request review is submitted, edited, or dismissed.", value: "pull_request_review"
      value "PULL_REQUEST_TARGET", "Triggered when activity on a pull request in the workflow's repository occurs.", value: "pull_request_target"
      value "PULL_REQUEST", "Triggered when activity on a pull request in the workflow's repository occurs.", value: "pull_request"
      value "PUSH", "Triggered when you push a commit or tag.", value: "push"
      value "REGISTRY_PACKAGE", "Triggered when activity related to GitHub Packages occurs in your repository.", value: "registry_package"
      value "RELEASE", "Triggered when release activity in your repository occurs.", value: "release"
      value "REPOSITORY_DISPATCH", "You can use the GitHub API to trigger a webhook event called repository_dispatch when you want to trigger a workflow for activity that happens outside of GitHub.", value: "repository_dispatch"
      value "SCHEDULE", "The schedule event allows you to trigger a workflow at a scheduled time.", value: "schedule"
      value "STATUS", "Triggered when the status of a Git commit changes.", value: "status"
      value "WATCH", "Triggered when the workflow's repository is starred.", value: "watch"
      value "WORKFLOW_DISPATCH", "Triggered manually by a user.", value: "workflow_dispatch"
      value "WORKFLOW_RUN", "Triggered when a workflow run is requested or completed.", value: "workflow_run"
    end
  end
end
