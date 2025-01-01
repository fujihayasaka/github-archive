# typed: true
# frozen_string_literal: true

class Codespaces::PrebuildConfigurationRunStatusComponent < ApplicationComponent
  attr_reader :configuration, :current_repo, :repo_owner, :actions_disabled

  CONFIGURATION_DISABLED = "Disabled"

  def initialize(configuration:, current_repo:, repo_owner:, actions_disabled:)
    @configuration = configuration
    @current_repo = current_repo
    @repo_owner = repo_owner
    @workflow_run = configuration.latest_workflow_run_for_display
    @actions_disabled = actions_disabled
  end

  def render?
    !actions_disabled
  end

  def workflow_run_status_for_display
    if configuration.disabled?
      CONFIGURATION_DISABLED
    elsif workflow_run_succeeded?
      safe_join ["Last run ", time_ago_in_words_js(workflow_run_completed_at)]
    else
      workflow_run_status_text
    end
  end

  private

  attr_reader :workflow_run

  def workflow_run_status_text
    if workflow_run&.in_progress? || workflow_run&.pending?
      "Currently Running"
    elsif workflow_run&.queued?
      "Queued..."
    elsif workflow_run&.cancelled?
      # Cancelled needs to be checked before failed? because
      # the cancelled state is considered failed in StatusCheckConfig::FAILURE_AND_INCOMPLETE_STATES
      "Cancelled"
    elsif workflow_run&.failed?
      "Failed"
    elsif workflow_run&.status.nil?
      "Never Run"
    else
      workflow_run&.conclusion&.titleize
    end
  end

  def see_output_url
    return unless !configuration.disabled? && check_run.present? && !workflow_run.pending?
    check_run.permalink(check_suite_focus: true)
  end

  def workflow_run_completed_at
    workflow_run&.completed_at
  end

  def workflow_run_succeeded?
    workflow_run&.succeeded?
  end

  def check_run
    workflow_run&.latest_workflow_run_job&.check_run
  end
end
