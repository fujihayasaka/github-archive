# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MobileEventContext < Platform::Enums::Base
      docs_category :meta
      required_capabilities [:mobile_only_schema_mask]
      description "Represents the different extra mobile context."

      # Notifications
      value "SAVE", "The notification was marked as saved.", value: "save"
      value "UNSAVE", "The notification was marked as unsaved.", value: "unsave"
      value "DONE", "The notification was marked as done.", value: "done"
      value "UNDONE", "The notification was marked as undone.", value: "undone"
      value "READ", "The notification was marked as read.", value: "read"
      value "UNREAD", "The notification was marked as unread.", value: "unread"
      value "SUBSCRIBE", "The notification list was subscribed to.", value: "subscribe"
      value "UNSUBSCRIBE", "The notification list was unsubscribed from.", value: "unsubscribe"
      value "FOCUSED", "The notification list is in focused mode.", value: "focused"
      value "NOT_FOCUSED", "The notification list is not in focused mode.", value: "not_focused"
      value "NOTIFICATIONS_ONBOARDING_FLOW", "The user has interacted with the notifications onboarding experience.", value: "notifications_onboarding_flow"

      # Pagers
      value "PAGE_ONE", "The user has navigated to the first page of a multi-page flow.", value: "page_one"
      value "PAGE_TWO", "The user has navigated to the second page of a multi-page flow.", value: "page_two"
      value "PAGE_THREE", "The user has navigated to the third page of a multi-page flow.", value: "page_three"
      value "PAGE_FOUR", "The user has navigated to the fourth page of a multi-page flow.", value: "page_four"
      value "PAGE_FIVE", "The user has navigated to the fifth page of a multi-page flow.", value: "page_five"
      value "PAGE_SIX", "The user has navigated to the sixth page of a multi-page flow.", value: "page_six"
      value "PAGE_SEVEN", "The user has navigated to the seventh page of a multi-page flow.", value: "page_seven"
      value "COMPLETE", "The user has completed a multi-page flow.", value: "complete"

      # Issue/Pull filters
      value "ISSUE_DETAILS", "The issue details are being viewed.", value: "issue_details"
      value "PULL_REQUEST_DETAILS", "The pull request details are being viewed.", value: "pull_request_details"
      value "PULL_REQUEST_FILES_CHANGED", "The pull request files changed are being viewed.", value: "pull_request_files_changed"
      value "CREATED", "The issue or pull request was created by the user.", value: "created"
      value "ASSIGNED", "The issue or pull request was assigned to the user.", value: "assigned"
      value "MENTIONED", "The issue or pull request mentioned the user.", value: "mentioned"
      value "REVIEW_REQUESTED", "The pull request requested review from the user.", value: "review_requested"
      value "CONTINUE_REVIEW", "The pull request review is ready to be continued by the user.", value: "continue_review"
      value "CLOSED", "The issue or pull request is closed.", value: "closed"
      value "OPEN", "The issue or pull request is open.", value: "open"

      # Commit
      value "COMMIT_DETAILS", "The commit details are being viewed.", value: "commit_details"

      # Workflow
      value "WORKFLOW_SUMMARY", "The workflow summary is being viewed.", value: "workflow_summary"
      value "WORKFLOW_RUNS", "The workflow runs are being viewed.", value: "workflow_runs"
      value "WORKFLOW_RUN_STEPS", "The workflow run steps are being viewed.", value: "workflow_run_steps"
      value "WORKFLOW_RUN_STEP_LOG", "The workflow step job log is being viewed.", value: "workflow_run_step_log"

      # Release notes
      value "DISPLAYED", "Release notes have been displayed to a user", value: "displayed"

      # Banner
      value "DISMISSED", "A banner (release notes, feature onboarding, etc.) dismissed by a user", value: "dismissed"
      value "OPENED", "A banner (release notes, feature onboarding, etc.) has been opened by a user", value: "opened"

      # Feed
      value "TRENDING", "An action on an item that is trending", value: "trending"
      value "AWESOME", "An action on an item as part of the default Awesome Lists topic", value: "awesome"
      value "FEED", "An action on an item that is part of the user's feed", value: "feed"

      # Agents
      value "AGENT_PULL_REQUESTS", "An action on the agent pull requests list", value: "agent_pull_requests"

      # Copilot
      value "COPILOT_UPSELL_BANNER_FLOW", "An action on the Copilot upsell flow", value: "copilot_upsell_banner_flow"
      value "COPILOT_HOME", "An action originating from the Copilot home screen", value: "copilot_home"
      value "COPILOT_THREADS", "An action originating from the Copilot threads screen", value: "copilot_threads"

      # Agent Tasks
      value "AGENT_TASKS_HOME", "An action originating from Agent Tasks from the home screen", value: "agent_tasks_home"
      value "AGENT_TASKS_REPOSITORY", "An action originating from Agent Tasks from the repository screen", value: "agent_tasks_repository"

      # Agent Assignment
      value "NEW_ISSUE", "An action originating from new issue creation", value: "new_issue"
      value "ISSUE_CELL", "An action originating from the issue cell quick menu", value: "issue_cell"
      value "AGENT_INSTRUCTIONS_INCLUDED", "Agent instructions were included when submitting", value: "agent_instructions_included"
      value "AGENT_INSTRUCTIONS_EMPTY", "No agent instructions were included when submitting", value: "agent_instructions_empty"
      value "HOME", "An action originating from the home screen", value: "home"
      value "REPOSITORY", "An action originating from the repository screen", value: "repository"
      value "COPILOT_CHAT", "An action originating from the Copilot Chat screen", value: "copilot_chat"
      value "COPILOT_CHAT_ASSISTANT_MESSAGE", "An action originating from the Copilot Chat assistant message", value: "copilot_chat_assistant_message"
      value "COPILOT_CHAT_INPUT_FIELD", "An action originating from the Copilot Chat input field", value: "copilot_chat_input_field"
      value "EXTERNAL", "An action originating from an external source", value: "external"
      value "REPOSITORY_FILE_VIEWER", "An action originating from the repository file viewer", value: "repository_file_viewer"
      value "PULL_REQUEST_FILES", "An action originating from the pull request files view", value: "pull_request_files"
      value "PULL_REQUEST_FILES_CHANGED_SINGLE_FILE", "An action originating from a single file in the pull request files changed view", value: "pull_request_files_changed_single_file"

      # Agent Logs
      value "AGENT_TASK_ACTIVE", "An action on an active agent task", value: "agent_task_active"
      value "AGENT_TASK_COMPLETED", "An action on a completed agent task", value: "agent_task_completed"
      value "AGENT_LOGS", "An action originating from the agent logs screen", value: "agent_logs"

      # Repository Creation
      value "CREATE_REPO_GENERAL", "An action on the General (step 1) page of repo creation", value: "create_repo_general"
      value "CREATE_REPO_CONFIGURATION", "An action on the Configuration (step 2) page of repo creation", value: "create_repo_configuration"
      value "PROFILE_REPOSITORIES", "An action originating from the profile repositories screen", value: "profile_repositories"
    end
  end
end
