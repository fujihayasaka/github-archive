# frozen_string_literal: true

module ChatopRetry # rubocop:disable Metrics/ModuleLength
  extend ActiveSupport::Concern
  include ChatopTimeRange

  VALID_RETRY_STATES = %i(processed_with_errors timed_out).freeze
  MAX_UPDATE_JOBS_TO_RETRY = 200_000
  RETRY_BATCH_SIZE = 100

  # rubocop:disable Metrics/BlockLength
  included do
    chatop :retry_timed_out, /retry[-_]timed[-_]out/,
           "retry-timed-out --from YYYY-MM-DD HH:MM --to YYYY-MM-DD HH:MM "\
           "(UpdateJob#created_at) --package-manager PACKAGE_MANAGER "\
           "--error-type ERROR_TYPE "\
           "--dry-run - Retry timed out jobs" do
      retry_update_jobs(params: jsonrpc_params, state: :timed_out)
    end

    chatop :retry_processed_with_errors, /retry[-_]processed[-_]with[-_]errors/,
           "retry-processed-with-errors --from YYYY-MM-DD HH:MM "\
           "--to YYYY-MM-DD HH:MM (UpdateJob#created_at) "\
           "--package-manager PACKAGE_MANAGER "\
           "--error-type ERROR_TYPE "\
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

      unless VALID_RETRY_STATES.include?(job.current_state.to_sym)
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

  # rubocop:disable Metrics/MethodLength
  def retry_update_jobs(params:, state:)
    retry_options = retry_options(params)
    return unless retry_options

    start_time = retry_options.fetch(:start_time)
    end_time = retry_options.fetch(:end_time)
    package_manager = retry_options.fetch(:package_manager)
    error_types = retry_options.fetch(:error_types)

    start_id, end_id = id_range_for_time_range(start_time, end_time)
    unless start_id && end_id
      jsonrpc_failure "No update jobs found in the specified time range"
      return
    end

    retried_count, max_jobs = retry_update_jobs_batched(
      start_id, end_id,
      state: state,
      package_manager: package_manager,
      error_types: error_types,
      start_time: start_time,
      end_time: end_time,
      dry_run: params["dry-run"]
    )

    jsonrpc_success build_retry_message(
      retried_count,
      start_time: start_time,
      end_time: end_time,
      error_types: error_types,
      max_jobs: max_jobs,
      dry_run: params["dry-run"]
    )
  end
  # rubocop:enable Metrics/MethodLength

  def retry_options(params)
    start_time, end_time = parse_retry_time_range(params)
    return nil unless start_time && end_time
    return nil unless valid_retry_time_range?(start_time, end_time)

    package_manager = params["package-manager"]
    return nil unless valid_package_manager?(package_manager)

    error_types = parse_error_types(params["error-type"])

    {
      start_time: start_time,
      end_time: end_time,
      package_manager: package_manager,
      error_types: error_types,
    }
  end

  def parse_retry_time_range(params)
    [DateTime.parse(params[:from]), DateTime.parse(params[:to])]
  rescue ArgumentError
    jsonrpc_failure "Invalid date format: from #{params[:from]}, " \
                    "to #{params[:to]}"
    [nil, nil]
  end

  def valid_retry_time_range?(start_time, end_time)
    return true if start_time >= 1.month.ago && end_time <= Time.now.utc

    jsonrpc_failure "Date range must be in the last month: " \
                    "from #{start_time}, to #{end_time}"
    false
  end

  def valid_package_manager?(package_manager)
    return true if package_manager.blank? || PackageManagers::ALL.include?(package_manager)

    jsonrpc_failure "Package manager must be one of " \
                    "#{PackageManagers::ALL.join(', ')}"
    false
  end

  def parse_error_types(error_type_param)
    return nil if error_type_param.blank?

    # Split by comma and strip whitespace from each type
    error_type_param.to_s.split(",").map(&:strip).compact_blank
  end

  # rubocop:disable Metrics/MethodLength
  def retry_update_jobs_batched(start_id, end_id, state:, package_manager:, error_types:, start_time:, end_time:,
                                dry_run:)
    retried_count = 0
    total_matching = 0
    max_jobs_exceeded = false

    each_id_batch(start_id, end_id) do |batch_start, batch_end|
      break if max_jobs_exceeded

      scope = build_retry_scope(batch_start, batch_end, state: state, package_manager: package_manager,
                                                        error_types: error_types, start_time: start_time,
                                                        end_time: end_time)

      # Count total matching jobs before last_update_run filter
      # Note: total_matching may be higher than retried_count because some jobs are
      # skipped if their last_update_run is newer than the end_time (line 189)
      batch_count = scope.count
      total_matching += batch_count

      # Check if we've exceeded the limit
      if total_matching > MAX_UPDATE_JOBS_TO_RETRY
        max_jobs_exceeded = true
        # Adjust batch_count to only process up to the limit
        batch_count = MAX_UPDATE_JOBS_TO_RETRY - (total_matching - batch_count)
      end

      # Process jobs with last_update_run filter
      processed = 0
      scope.includes(update_config: :last_update_run).find_each(batch_size: RETRY_BATCH_SIZE) do |job|
        break if processed >= batch_count

        processed += 1

        next if job.update_config.last_update_run&.created_at.to_i > end_time.to_i

        job.retry! unless dry_run
        retried_count += 1
      end
    end

    [retried_count, max_jobs_exceeded]
  end
  # rubocop:enable Metrics/MethodLength

  def build_retry_scope(batch_start, batch_end, state:, package_manager:, error_types:, start_time:, end_time:)
    scope = UpdateJob.where(id: batch_start..batch_end).
            where(created_at: start_time..end_time).
            in_state(state).
            joins(:update_config).
            merge(UpdateConfig.active)
    scope = scope.where(update_configs: { package_manager: package_manager }) if package_manager.present?
    if error_types.present?
      scope = scope.where(id: UpdateJobError.where(update_job_id: batch_start..batch_end,
                                                   error_type: error_types).select(:update_job_id).distinct)
    end
    scope
  end

  def build_retry_message(count, start_time:, end_time:, error_types:, max_jobs:, dry_run:)
    range_description = "created between #{start_time} and #{end_time}"
    error_detail = error_types.present? ? " with error-type #{error_types.join(', ')}" : ""
    max_detail = max_jobs_detail(max_jobs)

    return "dry-run: found #{count} update jobs to retry #{range_description}#{error_detail}#{max_detail}" if dry_run

    "Retried #{count} update jobs #{range_description}#{error_detail}#{max_detail}"
  end

  def max_jobs_detail(max_jobs)
    return "" unless max_jobs

    " (:warning: Didn't get all jobs in the time frame, " \
      "more than #{MAX_UPDATE_JOBS_TO_RETRY} jobs were found. " \
      "Re-run to get the next set)."
  end
end
