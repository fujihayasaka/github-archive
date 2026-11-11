# frozen_string_literal: true

module ChatopUpdateJobErrors
  extend ActiveSupport::Concern

  # rubocop:disable Metrics/BlockLength
  included do
    chatop :update_job_errors,
           /update[-_]job[-_]errors/,
           "update-job-errors "\
           "--from YYYY-MM-DD HH:MM --to YYYY-MM-DD HH:MM "\
           "--package-manager PACKAGE_MANAGER "\
           "--trigger-type UPDATE_JOB_TRIGGER_TYPE "\
           "--error-type UPDATE_JOB_ERROR_TYPE "\
           "- dry-run commands for update job errors (limited to 10)" do
      if jsonrpc_params[:from] && jsonrpc_params[:to]
        begin
          start_time = DateTime.parse(jsonrpc_params[:from])
          end_time = DateTime.parse(jsonrpc_params[:to])
        rescue ArgumentError
          jsonrpc_failure "Invalid date format: from #{jsonrpc_params[:from]},"\
                          " to #{jsonrpc_params[:to]}"
          return
        end
      end

      package_manager = jsonrpc_params["package-manager"]

      if package_manager.present? && PackageManagers::ALL.exclude?(package_manager)
        jsonrpc_failure "Package manager must be one of "\
                        "#{PackageManagers::ALL.join(', ')}"
        return
      end

      error_type = jsonrpc_params["error-type"]
      allowed_error_types = UpdateJobError::ALLOWED_UPDATE_JOB_ERROR_TYPES
      unless allowed_error_types.include?(error_type)
        jsonrpc_failure "Update job error type must be one of "\
                       "#{allowed_error_types.join(', ')}"
        return
      end

      trigger_type = jsonrpc_params["trigger-type"]
      if trigger_type.present? && UpdateJob::TRIGGER_TYPES.exclude?(trigger_type)
        jsonrpc_failure "Update job trigger type must be one of "\
                        "#{UpdateJob::TRIGGER_TYPES.join(', ')}"
        return
      end

      errored_jobs = find_update_job_errors(
        start_time: start_time,
        end_time: end_time,
        package_manager: package_manager,
        trigger_type: trigger_type,
        error_type: error_type,
      ).map(&:update_job)

      return jsonrpc_success "No update job errors where found" if errored_jobs.empty?

      lines = errored_jobs.map do |update_job|
        next unless update_job.update_config.repo.account.active?

        [
          ".dependabot job #{update_job.id}",
          DryRunPresenter.new(update_job: update_job).command,
        ]
      end
      jsonrpc_success((["```"] + lines.compact + ["```"]).join("\n\n"))
    end
  end
  # rubocop:enable Metrics/BlockLength

  def find_update_job_errors(start_time:, end_time:, package_manager:,
                             trigger_type:, error_type:)
    errors = UpdateJobError.
             joins(:repo).
             where(error_type: error_type).
             where(repos: { private: false })

    errors = errors.where(update_configs: { package_manager: package_manager }) if package_manager.present?

    errors = errors.where(update_jobs: { trigger_type: trigger_type }) if trigger_type.present?
    errors = errors.where(created_at: start_time..end_time) if start_time && end_time
    errors.order(id: :desc).limit(20)
  end
end
