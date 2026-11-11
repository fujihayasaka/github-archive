# frozen_string_literal: true

module ChatopJob
  extend ActiveSupport::Concern

  # rubocop:disable Metrics/BlockLength
  included do
    chatop(:job, /job\s*(?<job_id>\d+)?/, <<~DESC) do
      NAME
        job -- List update job information

      SYNOPSIS

        job [update_job_id | --github-request-id | --pr] [--set-timeout]

        --github-request-id     The GitHub request id to filter by
        --pr                    An owner/repo#pr-id to filter by
        --set-timeout=seconds   Maximum timeout in seconds
        --dry-run               Print the dry-run command to reproduce the job

      EXAMPLES

        List the details for job with id `1`

          job 1

        List the details for the job associated with GitHub request id `a0490bcf-87aa-422b-88c6-37d1029a5c27`

          job --github-request-id a0490bcf-87aa-422b-88c6-37d1029a5c27

        Update the maximum job timeout for job with id `1` to 2 hours

          job 1 --set-timeout 7200

        List the details for job that created a PR

         job --pr dependabot/dependabot-core#1234
    DESC
      begin
        job = fetch_job(params: jsonrpc_params)
      rescue ActiveRecord::RecordNotFound
        jsonrpc_failure "Couldn't find job."
        return
      end

      update(job, jsonrpc_params)

      # Header
      lines = ["Job #{job.id} - #{job.trigger_type}"]
      lines << "Dependencies: #{job.dependencies.join(', ')}" if job.dependencies

      lines << "Actions workflow run id: #{job.actions_workflow_run_id}" if job.actions?

      if jsonrpc_params["dry-run"]
        lines << "Repository: #{job.update_config.repo.github_url} "
        lines << if job.update_config.repo.private?
                   "(private) dry-run this update using dependabot-update-debugger:"
                 else
                   "(public) dry-run this update in dependabot-core:"
                 end

        presenter = DryRunPresenter.new(update_job: job)
        lines << presenter.command + "\n"

        lines << "dry-run this update using the Dependabot CLI:"
        lines << "```"
        lines << presenter.cli_command
        lines << "```"
      end

      # Timeline
      lines << "* #{job.created_at} - created"
      previous_line_created_at = job.created_at
      job.update_job_transitions.each do |t|
        duration = ActiveSupport::Duration.build(
          t.created_at - previous_line_created_at
        ).iso8601.downcase.gsub(/[pt]/, "")
        previous_line_created_at = t.created_at
        lines << "* #{t.created_at} - #{t.to_state} (after #{duration})"
      end

      if job.unique_errors.any?
        lines << ""
        lines << "errors: "
        job.unique_errors.each do |e|
          lines << "* #{e.error_type} - #{e.error_presenter.issue_body}"
        end
      end

      lines << "\nPull Request activity in [Splunk](#{Activity::Splunk.new(update_job: job).table_url})"
      lines << "\nUpdate Job events in [Splunk](#{Activity::Splunk.new(update_job: job).api_logs_url})"
      lines << "\nJob-related Monolith events in [Splunk](#{Activity::Splunk.new(update_job: job).monolith_logs_url})"

      jsonrpc_success lines.join("\n")
    end
  end
  # rubocop:enable Metrics/BlockLength

  private

  def fetch_job(params:)
    job_id = params[:job_id]
    github_request_id = params["github-request-id"]
    pr = params["pr"]

    if github_request_id
      UpdateJob.
        where(github_request_id: github_request_id.to_i).
        first!
    elsif pr
      if pr.include?("https://github.com/")
        account, repo, pr_number = pr.match(%r{github.com/([^/]+)/([^/]+)/pull/(\d+)}).captures
      else
        account, repo, pr_number = pr.match(%r{([^/]+)/([^/]+)#(\d+)}).captures
      end
      account = Account.find_by(github_login: account)
      repo = Repo.find_by!(account: account, name: repo)
      pr = repo.pull_requests.find_by!(github_number: pr_number)
      pr.update_job
    else
      UpdateJob.find(job_id.to_i)
    end
  end

  def update(job, params)
    return if params["set-timeout"].blank?

    Rails.cache.write(
      job.max_updater_run_time_cache_key, params["set-timeout"],
      expires_in: 1.day
    )
  end
end
