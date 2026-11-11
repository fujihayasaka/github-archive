# typed: true
# frozen_string_literal: true

class Actions::Graph::GroupComponent < ApplicationComponent
  def initialize(group:, workflow_run:, execution: nil, retry_blankstate: false, pull_request_number: nil)
    @group = group
    @workflow_run = workflow_run
    @execution = execution
    @retry_blankstate = retry_blankstate
    @pull_request_number = pull_request_number
  end

  private

  attr_reader :group, :workflow_run

  def workflow_job_runs
    group.workflow_job_runs
  end

  def single_job_group?
    !group.matrix? && group.jobs.size <= 1
  end

  def show_header?
    group.matrix?
  end

  def header_text
    "Matrix: #{group.title}"
  end
end
