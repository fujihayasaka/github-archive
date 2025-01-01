# typed: true
# frozen_string_literal: true

# Given an issue that has been converted into a hierarchy model, call out to the
# issues graph API to update the data in the issues graph data store.
class SyncIssueToIssuesGraphJob < ApplicationJob
  queue_as :sync_issue_to_issues_graph

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(issue_hierarchy_model)
    GitHub
      .issues_graph_api_client
      .update_issue(issue: issue_hierarchy_model, stat_tags: ["context:sync_issue_to_issues_graph_job"])
  end
end
