# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength
module ChatopRetry
  extend ActiveSupport::Concern

  MAX_UPDATE_JOBS_TO_RETRY = 5000

  # rubocop:disable Metrics/BlockLength
  included do
    chatop :retry_timed_out, /retry[-_]timed[-_]out/,
           "retry-timed-out --from YYYY-MM-DD HH:MM --to YYYY-MM-DD HH:MM "\
           "(UpdateJob#created_at) --package-manager PACKAGE_MANAGER "\
           "--dry-run - Retry timed out jobs" do
      retry_update_jobs(params: jsonrpc_params, state: :timed_out)
    end

    chatop :retry_cancelled, /retry[-_]cancell?ed/,
           "retry-cancelled "\
           "--from YYYY-MM-DD HH:MM "\
           "--to YYYY-MM-DD HH:MM "\
           "--package-manager PACKAGE_MANAGER "\
           "--dry-run - Retry cancelled jobs" do
      retry_update_jobs(params: jsonrpc_params, state: :cancelled)
    end

    chatop :retry_processed_with_errors, /retry[-_]processed[-_]with[-_]errors/,
           "retry-processed-with-errors --from YYYY-MM-DD HH:MM "\
           "--to YYYY-MM-DD HH:MM (UpdateJob#created_at) "\
           "--package-manager PACKAGE_MANAGER "\
           "--dry-run - Retry processed with errors jobs" do
      retry_update_jobs(params: jsonrpc_params, state: :processed_with_errors)
    end

    # The regex needs to match ".dependabot retry" when "--github-request-id ID"
    # is passed. "retry_timed_out" is defined first to avoid clashing.
    chatop :retry,
           /retry\s*(?<job_id>\d+)?/,
           "retry UPDATE_JOB_ID or retry --github-request-id ID - "\
           "Retry the update job" do
      job_id = fetch_job_id(params: jsonrpc_params)
      job = UpdateJob.find_by(id: job_id)

      unless job
        jsonrpc_failure "Couldn't find update job #{job_id}."
        return
      end

      valid_states = %i(processed_with_errors timed_out cancelled)
      unless valid_states.include?(job.current_state.to_sym)
        jsonrpc_failure "Job must be processed_with_errors or timed_out, "\
                        "current_state: #{job.current_state}."
        return
      end

      job.retry!

      jsonrpc_success "Enqueued update job retry #{job_id}"
    end
  end
  # rubocop:enable Metrics/BlockLength

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

  # rubocop:disable Metrics/AbcSize
  # rubocop:disable Metrics/CyclomaticComplexity
  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/PerceivedComplexity
  def retry_update_jobs(params:, state:)
    begin
      start_time = DateTime.parse(params[:from])
      end_time = DateTime.parse(params[:to])
    rescue ArgumentError
      jsonrpc_failure "Invalid date format: from #{params[:from]}, "\
                      "to #{params[:to]}"
      return
    end

    if start_time < 1.month.ago || end_time > Time.now.utc
      jsonrpc_failure "Date range must be in the last month: "\
                      "from #{start_time}, to #{end_time}"
      return
    end

    package_manager = params["package-manager"]
    if package_manager.present? &&
       PackageManagers::ALL.exclude?(package_manager)
      jsonrpc_failure "Package manager must be one of "\
                      "#{PackageManagers::ALL.join(', ')}"
      return
    end

    jobs = UpdateJob.
           where(created_at: start_time..end_time).
           in_state(state).includes(update_config: :last_update_run).
           joins(:update_config).merge(UpdateConfig.active).
           limit(MAX_UPDATE_JOBS_TO_RETRY + 1)
    jobs = jobs.where(update_configs: { package_manager: package_manager }) if package_manager.present?
    max_jobs = jobs.count > MAX_UPDATE_JOBS_TO_RETRY
    jobs = jobs.first(MAX_UPDATE_JOBS_TO_RETRY)

    jobs_to_retry = jobs.reject do |job|
      job.update_config.last_update_run&.created_at.to_i > end_time.to_i
    end

    range_description = "created between #{start_time} and #{end_time}"
    max_detail = ""
    if max_jobs
      max_detail = " (:warning: Didn't get all jobs in the time frame, "\
                  "more than #{MAX_UPDATE_JOBS_TO_RETRY} jobs where found. "\
                  "Re-run to get the next set)."
    end

    if params["dry-run"]
      jsonrpc_success "dry-run: found #{jobs_to_retry.count} update jobs to "\
                      "retry #{range_description}#{max_detail}"
      return
    end

    jobs_to_retry.each(&:retry!)

    jsonrpc_success "Retried #{jobs_to_retry.count} update jobs "\
                    "#{range_description}#{max_detail}"
  end
  # rubocop:enable Metrics/AbcSize
  # rubocop:enable Metrics/CyclomaticComplexity
  # rubocop:enable Metrics/MethodLength
  # rubocop:enable Metrics/PerceivedComplexity
end
# rubocop:enable Metrics/ModuleLength
