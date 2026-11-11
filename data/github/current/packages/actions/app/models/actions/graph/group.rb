# typed: true
# frozen_string_literal: true

class Actions::Graph::Group
  GROUP_TYPE_DEFAULT = 0
  GROUP_TYPE_MATRIX = 1
  GROUP_TYPE_STRATEGY_EXPRESSION = 2
  GROUP_TYPE_WORKFLOW_MATRIX = 3

  attr_reader :workflow_job_runs, :group

  def initialize(group:, workflow_job_runs:)
    @group = group
    @workflow_job_runs = workflow_job_runs
  end

  def dom_id
    @dom_id ||= group_dom_id(group[:id])
  end

  def id
    group[:id]
  end

  def id_hash
    Base64.encode64(id).strip
  end

  def parent_job_id
    jobs&.first.id if matrix?
  end

  def jobs
    @keyed_workflow_job_runs ||= workflow_job_runs.group_by(&:parent_job_id)
    @jobs ||= (group[:jobs] || [])
      .map { |job| Actions::Graph::Job.new(job: job, workflow_job_run: @keyed_workflow_job_runs[job[:id]]&.first) }
      .sort_by { |graph_job| graph_job.check_run_sort_order }
  end

  def matrix_jobs
    return [] unless matrix?

    workflow_job_runs.collect do |workflow_job_run|
      Actions::Graph::Job.new(job: { id: jobs&.first.id, name: workflow_job_run.check_run&.display_name }, workflow_job_run: workflow_job_run)
    end
  end

  def inputs
    (group[:inputs] || []).map { |input| group_dom_id(input) }
  end

  def outputs
    (group[:outputs] || [])
      .reject { |output| output.empty? }
      .map { |output| group_dom_id(output) }
  end

  def matrix?
    group_type == GROUP_TYPE_MATRIX || group_type == GROUP_TYPE_STRATEGY_EXPRESSION || group_type == GROUP_TYPE_WORKFLOW_MATRIX
  end

  def workflow_matrix?
    group_type == GROUP_TYPE_WORKFLOW_MATRIX
  end

  def title
    "" unless matrix?

    group[:name] || jobs.first.id
  end

  def in_progress?
    conclusion == "in_progress"
  end

  def completed_jobs_count
    @completed_jobs_count ||= workflow_job_runs.count { |run| run.check_run&.completed? }
  end

  def jobs_count
    workflow_job_runs.size
  end

  def conclusion
    @conclusion ||= if status == "completed"
      calculate_conclusion
    elsif status == "in_progress"
      "in_progress"
    else
      nil
    end
  end

  # Give more priority to in_progress so rollup will be in_progress if one job is in_progress
  STATUS_HIERARCHY = %w(in_progress requested waiting pending queued completed)
  CONCLUSIONS_HIERARCHY = %w(action_required stale timed_out failure cancelled success neutral skipped)

  def status
    @status ||= calculate_status
  end

  private

  def calculate_status
    lowest_run = workflow_job_runs.min_by { |run| STATUS_HIERARCHY.index(run.check_run&.status || "requested") }
    lowest_run&.check_run&.status || "requested"
  end

  def calculate_conclusion
    lowest_run = workflow_job_runs.min_by { |run| CONCLUSIONS_HIERARCHY.index(run.check_run.conclusion) }
    lowest_run&.check_run.conclusion
  end

  def group_dom_id(id)
    "group-#{id.gsub(/[^0-9A-Za-z\-\_]/, "_")}"
  end

  def group_type
    group[:type]
  end
end
