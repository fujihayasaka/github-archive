# typed: true
# frozen_string_literal: true

class Actions::WorkflowRunItemComponent < ApplicationComponent
  include BotHelper

  def initialize(workflow_run_item:, user_has_push_access:, current_repository:, user_is_site_admin:)
    @workflow_run = workflow_run_item
    @user_has_push_access = user_has_push_access
    @current_repository = current_repository
    @user_is_site_admin = user_is_site_admin
  end

  private

  attr_reader :workflow_run, :user_has_push_access, :current_repository, :user_is_site_admin

  delegate :number, to: :pull_request, prefix: true, allow_nil: true
  delegate :head_sha, :name, :repository, :head_branch, to: :workflow_run

  memoize def trigger
    workflow_run.trigger
  end

  memoize def pull_request
    if trigger.is_a? PullRequest
      @_pull_request = trigger
    else
      @_pull_request ||= repository.pull_requests.find_by(
        head_sha: head_sha,
        head_ref: head_branch,
        head_repository_id: head_repository_id,
      )
    end

    @_pull_request = nil if @_pull_request&.user&.spammy?

    @_pull_request
  end

  def workflow_actor
    workflow_run.actor
  end

  def show_options_menu?
    return true if can_cancel_workflow_run?
    return true if pull_request.present?
    return true if can_view_workflow_file?
    return true if can_delete_workflow_run?

    false
  end

  def ref_name_relevant?
    workflow_run.ref_name_relevant?
  end

  def can_cancel_workflow_run?
    workflow_run.check_suite.cancelable? && user_has_push_access
  end

  def show_options_divider?
    pull_request || can_view_workflow_file? || can_delete_workflow_run?
  end

  def head_repository_id
    workflow_run.check_suite.head_repository_id
  end

  def workflow_run_title
    title = if repository.feature_flag_enabled?(:actions_workflow_title_markdown, default: true)
      helpers.title_markdown(workflow_run.title)
    else
      workflow_run.title
    end

    title || Actions::WorkflowRun::PLACEHOLDER_TITLE
  end

  def can_delete_workflow_run?
    user_has_push_access && workflow_run.deleteable?
  end

  def can_view_workflow_file?
    workflow_run.can_user_view_workflow_file?(current_user)
  end

  def can_view_link_to_stafftools?
    user_is_site_admin
  end

  def user_is_workflow_actor?
    workflow_actor == current_user
  end

  def show_spammy_label?
    workflow_actor&.spammy? && current_user&.site_admin?
  end

  def show_action_actor?
    ![Actions::TriggerTypes::SCHEDULE, Actions::TriggerTypes::MERGE_GROUP].include? trigger_type
  end

  def trigger_type
    Actions::TriggerTypes.call(workflow_run: workflow_run)
  end

  def show_disruptive_workflow
    workflow_actor&.spammy? && !user_is_workflow_actor? && !current_user&.site_admin?
  end

  def render?
    workflow_run.check_suite.present?
  end

  def status_component
    Actions::WorkflowRuns::StatusComponent.new(
      conclusion: workflow_run.conclusion,
      status: workflow_run.status,
      is_job: false,
      size: 16,
      style: "margin-top: 2px",
    )
  end

  def status_component_aria_label
    status_component.aria_text
  end

  def workflow_run_link_aria_label
    if workflow_run.title == workflow_run.workflow_name
      "#{status_component_aria_label} Run #{workflow_run.run_number} of #{workflow_run.workflow_name}."
    else
      "#{status_component_aria_label} Run #{workflow_run.run_number} of #{workflow_run.workflow_name}. #{workflow_run.title}"
    end
  end
end
