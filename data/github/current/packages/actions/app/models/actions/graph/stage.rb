# typed: true
# frozen_string_literal: true

class Actions::Graph::Stage
  attr_reader :workflow_job_runs

  def initialize(stage:, workflow_job_runs:)
    @stage = stage
    @workflow_job_runs = workflow_job_runs
  end

  def groups
    @parent_keyed_workflow_job_runs ||= workflow_job_runs.group_by(&:parent_job_id)
    @groups ||= (@stage[:groups] || []).map do |group|
      if group[:type] == Actions::Graph::Group::GROUP_TYPE_WORKFLOW_MATRIX
        parent_id = group[:jobs].first[:id]
        filtered_workflow_job_runs = workflow_job_runs.filter { |job_run| job_run&.parent_job_id&.starts_with?("#{parent_id}.") }
      else
        filtered_workflow_job_runs = (group[:jobs] || []).map do |job|
          @parent_keyed_workflow_job_runs[job[:id]]
        end.flatten.compact
      end

      Actions::Graph::Group.new(group: group, workflow_job_runs: filtered_workflow_job_runs)
    end
  end
end
