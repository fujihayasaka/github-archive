# frozen_string_literal: true

module ChatopLogs
  extend ActiveSupport::Concern

  included do
    chatop :logs,
           /logs\s*(?<job_id>\d+)?/,
           "logs UPDATE_JOB_ID OR logs --github-request-id ID - "\
           "Logs for an update job" do
      job_id = fetch_job_id(params: jsonrpc_params)
      job = UpdateJob.find_by(id: job_id)
      unless job
        jsonrpc_failure "Couldn't find update job #{job_id}."
        return
      end
      if job.actions?
        handle_actions_runner_logs(job)
      else
        handle_aws_runner_logs(job, job_id: job_id)
      end
    end
  end

  private

  def fetch_job_id(params:)
    job_id = params[:job_id]
    github_request_id = params["github-request-id"]

    if github_request_id
      UpdateJob.
        where(github_request_id: github_request_id.to_i).
        pick(:id)
    else
      job_id.to_i
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

  def handle_aws_runner_logs(job, job_id:)
    # Job uses AWS runner
    logs = UpdateJobLogs.new(job)

    if logs.staff_readable.empty?
      jsonrpc_failure "Couldn't find logs for job #{job_id}. If you've " \
                      "provided a valid update job id, it's probably " \
                      "because logs get deleted after "\
                      "#{UpdateJobLogs::DEPENDABOT_UPDATE_JOB_LOG_RETENTION_DAYS} days"
      return
    end

    lines = ["```"]
    lines << logs.staff_readable
    lines << "```"

    jsonrpc_success lines.join("\n")
  end
end
