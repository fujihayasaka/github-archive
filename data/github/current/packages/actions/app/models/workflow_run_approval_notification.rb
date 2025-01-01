# typed: true
# frozen_string_literal: true

class WorkflowRunApprovalNotification
  include GlobalID::Identification

  attr_reader :workflow_run

  delegate :async_notifications_list,
    :creator_id,
    :global_relay_id,
    :notifications_list,
    :notifications_thread,
    :permalink,
    :repository,
    :created_at,
    :check_suite,
    :updated_at,
    to: :workflow_run

  # Public: Find the WorkflowRun for the given id and wrap it with
  # WorkflowRunApprovalNotification.
  #
  # We want to distinguish between a WorkflowRun that requires approval at one point
  # and the same workflowrun with a different completion status, so the id value
  # we will pass consists of the WorkflowRun id, some timestamp, and the approvals keyword
  # to ensure uniqueness. Check suites and workflow runs are tied together 1:1 however standard
  # workflow run completed/failed notifications use check suites as the main thread while approvals
  # use the workflow_run
  #
  # id - The WorkflowRun primary key id + timestamp
  #
  # Returns a WorkflowRunApprovalNotification or nil if none exists
  # for the id.
  #
  # rubocop:disable GitHub/FindByDef
  def self.find_by_id(id)
    workflow_run_id, _timestamp = id.split(";")

    if workflow_run = Actions::WorkflowRun.find(workflow_run_id)
      new(workflow_run)
    end
  end

  def self.find(id)
    find_by_id(id)
  end

  def initialize(workflow_run)
    @workflow_run = workflow_run
  end

  # deliver the notification regardless of the continuous_integration_failures_only setting
  def deliver?(settings)
    true
  end

  def id
    [workflow_run.id, updated_at.to_i].join(";")
  end

  # This is needed for the email inbox snippet
  def body
    "[#{repository.name_with_display_owner}] #{workflow_run.name}: Your review was requested to deploy"
  end
  alias body_html body

  # For Newsies::Emails::CheckSuiteEventNotification message construction
  # Unique identifier for this workflow run update
  def message_id
    "<#{repository.name_with_display_owner}/workflow-run/#{global_relay_id}/#{updated_at.to_i}@#{GitHub.urls.host_name}>"
  end

  # The sender of the notification (must be a `User`) - in this case, the
  # creator of the check suite associated with the workflow run because they triggered the run. See
  # `Newsies::Emails::Message` for usage.
  def notifications_author
    user
  end

  # This is used in web notifications to indicate who triggered the event.
  # See NotificationSummary#summarize_comment for more information.
  def user
    workflow_run.check_suite.creator
  end

  def user_id
    workflow_run.check_suite.creator_id
  end

  # Overrides for Summarizable#get_notification_summary
  def get_notification_summary
    list = Newsies::List.to_object(notifications_list)
    thread = Newsies::List.to_object(notifications_thread)
    GitHub.newsies.web.find_rollup_summary_by_thread(list, thread)
  end
end
