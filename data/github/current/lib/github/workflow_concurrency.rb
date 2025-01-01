# typed: true
# frozen_string_literal: true

module GitHub::WorkflowConcurrency
  def blocking_resources(concurrency, owner)
    return [] unless concurrency.present?

    concurrency_json = JSON.parse(concurrency)
    waiting_on_resource = concurrency_json["waiting_on_resource"]
    blocking_check_suite = nil
    blocking_check_run = nil
    return [] unless waiting_on_resource.present?

    if waiting_on_resource["check_run_id"].present?
      blocking_check_run = CheckRun.find_by(id: waiting_on_resource["check_run_id"].to_i)
      return unless blocking_check_run.present?
      [{
        display_name: blocking_check_run.display_name,
        url:  blocking_check_run.permalink,
        display_type: "job"
      }]
    elsif waiting_on_resource["check_suite_id"].present?
      blocking_check_suite = CheckSuite.find_by(id: waiting_on_resource["check_suite_id"].to_i)
      return unless blocking_check_suite.present?
      return [{
        display_name: blocking_check_suite.name,
        url:  blocking_check_suite.permalink,
        display_type: "run"
      }] unless waiting_on_resource["identifier"].present?

      # if identifier is present, fetch the jobs that are part of this reference workflow
      # jobs stores `parent_job_id` with format <identifier>.<jobId>
      blocking_jobs = blocking_check_suite.workflow_run&.latest_workflow_job_runs&.where("parent_job_id LIKE ?", "#{waiting_on_resource["identifier"]}.%")
      blocking_jobs.filter_map do |job|
        {
          display_name: job.check_run&.display_name,
          url:  job.check_run.permalink,
          display_type: "job"
        } if job.check_run&.status != "completed"
      end
    else
      []
    end
  end
end
