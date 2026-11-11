
# typed: true
# frozen_string_literal: true

class Actions::Graph::MatrixComponent < ApplicationComponent
  def initialize(group:, workflow_run:, execution: nil, expanded: false, retry_blankstate: false, pull_request_number: nil)
    @group = group
    @workflow_run = workflow_run
    @execution = execution
    @expanded = expanded
    @retry_blankstate = retry_blankstate
    @pull_request_number = pull_request_number
  end

  private

  attr_reader :group, :workflow_run

  def matrix_path(expanded:)
    actions_graph_matrix_path(
      user_id: workflow_run.repository.owner_display_login,
      repository: workflow_run.repository,
      workflow_run_id: workflow_run.id,
      matrix_id_hash: group.id_hash,
      expanded: expanded,
      attempt: @execution&.attempt,
      pr: @pull_request_number
    )
  end

  def expanded?
    !!@expanded
  end

  def workflow_job_runs
    group.workflow_job_runs
  end

  def job_parent_key
    workflow_job_runs.first&.parent_job_id
  end

  def channel
    if group.workflow_matrix? && workflow_run.check_suite
      GitHub::WebSocket::Channels.check_suite(workflow_run.check_suite)
    else
      GitHub::WebSocket::Channels.workflow_job_run(workflow_run.id, group.parent_job_id)
    end
  end

  # True when rendering the latest execution or the overall checksuite status
  memoize def viewing_current?
    @execution.nil? || (@execution.is_latest_execution? && !@workflow_run.processing_retry?) || @retry_blankstate
  end
end
