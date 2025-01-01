# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class IssueBulkInput < Platform::Inputs::Base
      description "Specifies the attributes for an issue bulk update."
      MAX_ISSUES = 1000
      TTL = 10.minutes
      DATADOG_METRIC_NAME = "platform.issue_bulk_update"

      argument :state, Enums::IssueState, "The desired issue state.", required: false
      argument :state_reason, Enums::IssueClosedStateReason, "The reason the issue is to be closed.", required: false
      argument :apply_label_ids, [ID], "An array of Node IDs of labels to add to each issue in the list of issues.", required: false, loads: Objects::Label
      argument :remove_label_ids, [ID], "An array of Node IDs of labels to remove from each issue in the list of issues.", required: false, loads: Objects::Label
      argument :apply_assignee_ids, [ID], "An array of Node IDs of users to add as assignees to each issue in the list of issues.", required: false, loads: Interfaces::Actor
      argument :remove_assignee_ids, [ID], "An array of Node IDs of users to remove as assignees from each issue in the list of issues.", required: false, loads: Interfaces::Actor
      argument :milestone_id, ID, "The Node ID of the milestone to add to each issue in the list of issues.", required: false, loads: Objects::Milestone
      argument :clear_milestone, Boolean, "Whether to clear the milestone from each issue in the list of issues.", required: false
      argument :add_to_project_v2_ids, [ID], "An array of Node IDs of projects to add each issue in the list of issues to.", required: false, loads: Objects::ProjectV2
      argument :remove_from_project_v2_ids, [ID], "An array of Node IDs of projects to remove each issue in the list of issues from.", required: false, loads: Objects::ProjectV2
      argument :issue_type_id, ID, "The Node ID of the issue type to set for each issue in the list of issues", required: false
      argument :unset_issue_type, Boolean, "Whether to unset the issue type for each issue in the list of issues", required: false
    end
  end
end
