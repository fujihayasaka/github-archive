# typed: true
# frozen_string_literal: true

class Actions::Graph::GraphComponent < ApplicationComponent
  include HydroHelper

  def initialize(
    graph:,
    workflow_run:,
    execution: nil,
    retry_blankstate: false,
    pull_request_number: nil)
    @graph = graph
    @workflow_run = workflow_run
    @execution = execution
    @retry_blankstate = retry_blankstate
    @pull_request_number = pull_request_number
  end

  private

  attr_reader :graph, :workflow_run

  def pull_request_number
    # Validate that the pull request ID from the request parameters belongs to a valid pull request so that job links in the graph only have valid PR query parameters
    if @pull_request_number && current_repository
      pull = PullRequest.with_number_and_repo(@pull_request_number, current_repository)
      pull.number if pull
    end
  end

  def show_graph?
    @graph.present? && !stale_workflow_run?
  end

  def stale_workflow_run?
    # Workflows there were run before the `workflow_job_run` table was created (and populated)
    # cannot show the correct state in all cases. We want to hide them instead.
    @workflow_run.updated_at <= Time.parse("2020-10-29 00:00:00 UTC")
  end

  def update_on_execution_change?
    @execution.present? && @execution.is_latest_execution?
  end
end
