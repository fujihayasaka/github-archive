# typed: true
# frozen_string_literal: true

class Actions::Graph::JobComponent < ApplicationComponent
  include StatusHelper
  include HydroHelper
  include FeatureFlagHelper

  def initialize(job:, workflow_run:, execution: nil, is_matrix: false, retry_blankstate: false, parent_group: nil, pull_request_number: nil)
    @job = job
    @workflow_run = workflow_run
    @execution = execution
    @is_matrix = is_matrix
    @repo_owner = @workflow_run.repository.owner
    @retry_blankstate = retry_blankstate
    @parent_group = parent_group
    @pull_request_number = pull_request_number
  end

  private

  attr_reader :job, :workflow_run, :is_matrix

  def channel
    return check_run.channel if check_run

    GitHub::WebSocket::Channels.workflow_job_run(workflow_run.id, job.id)
  end

  def check_run
    job.workflow_job_run&.check_run
  end

  def viewing_current?
    @execution.nil? || @execution.is_latest_execution? || @retry_blankstate
  end

  def title_styles
    check_run ? "color-fg-default" : "color-fg-muted"
  end

  def show_timing?
    check_run&.seconds_to_completion.present? || (check_run&.started_at.present? && check_run&.in_progress?)
  end

  def show_deployment_progress?
    check_run&.in_progress? && deployment&.environment
  end

  def deployment
    check_run&.deployment
  end

  def deployment_steps_count
    deployment_steps.size
  end

  def deployment_steps
    @steps ||= check_run.passthrough_steps? ? check_run.steps_from_backend : check_run.get_steps

    @deployment_steps ||= @steps.map.with_index do |step, index|
      next if index == 0 && step.name == "Set up job"
      next if index + 1 == @steps.size && step.name == "Complete job"

      step
    end.compact
  end

  memoize def deployment_steps_by_completion
    deployment_steps.group_by(&:completed?)
  end

  def complete_deployment_steps
    deployment_steps_by_completion[true] || []
  end

  def incomplete_deployment_steps
    deployment_steps_by_completion[false] || []
  end

  def display_name
    job.name
  end

  def job_title_id
    "workflow-job-name-#{job.id}"
  end

  def can_split_name?
    @job.workflow_job_run&.reusable_job? || @job.reusable_job?
  end

  def custom_gate_requests
    requests = check_run&.custom_gate_requests.sort_by(&:id)
    {
      first_integration_name: requests&.first&.gate&.integration&.name,
      size: requests&.size || 0
    }
  end
end
