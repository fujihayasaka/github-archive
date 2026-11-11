# typed: true
# frozen_string_literal: true

class Actions::Graph::Job
  attr_reader :workflow_job_run

  def initialize(job:, workflow_job_run:)
    @job = job
    @workflow_job_run = workflow_job_run
  end

  def name
    workflow_job_run&.check_run&.display_name || @job[:name] || @job[:id]
  end

  def id
    @job[:id]
  end

  def reusable_job?
    id.include?(".")
  end

  def check_run_sort_order
    # If there is no check run yet, use similar logic as in check run to create a sort order
    # Note: `number` is always 0 for actions check runs, so using the max value here.
    workflow_job_run&.check_run&.sort_order || [CheckRun::MAX_NUMBER_VALUE, StatusCheckConfig::STATE_SORT_ORDER["expected"], name]
  end
end
