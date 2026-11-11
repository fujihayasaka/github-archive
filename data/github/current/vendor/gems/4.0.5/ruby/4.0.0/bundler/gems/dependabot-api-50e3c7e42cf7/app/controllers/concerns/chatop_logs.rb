# frozen_string_literal: true

module ChatopLogs
  extend ActiveSupport::Concern

  included do
    chatop :logs,
           /logs\s*(?<job_id>\d+)?/,
           "logs UPDATE_JOB_ID OR logs --github-request-id ID OR logs --pr owner/repo#123 - "\
           "Logs for an update job" do
      job = fetch_job_for_logs(params: jsonrpc_params)
      unless job
        jsonrpc_failure "Couldn't find update job."
        return
      end
      handle_actions_runner_logs(job)
    end
  end

  private

  def fetch_job_for_logs(params:)
    job_id = params[:job_id]
    github_request_id = params["github-request-id"]
    pr = params["pr"]

    if github_request_id
      UpdateJob.find_by(github_request_id: github_request_id.to_i)
    elsif pr
      find_update_job_from_pr(pr)
    else
      UpdateJob.find_by(id: job_id.to_i)
    end
  end

  def handle_actions_runner_logs(job)
    if job.actions_workflow_run_id.present?
      nwo = job.repo.full_name
      workflow_run_id = job.actions_workflow_run_id
      url = "https://admin.github.com/stafftools/repositories/#{nwo}/actions_latest_runs?query=#{workflow_run_id}"
      jsonrpc_success "Access the logs directly: #{url}"
    else
      jsonrpc_failure "Couldn't find workflow run ID for job #{job.id}. If you've " \
                      "provided a valid update job id, it's probably " \
                      "because the job did not trigger a workflow run."
    end
  end
end
