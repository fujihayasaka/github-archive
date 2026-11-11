# frozen_string_literal: true

module ChatopFailed # rubocop:disable Metrics/ModuleLength
  extend ActiveSupport::Concern
  include ChatopTimeRange

  FAILED_STATES = %i(timed_out processed_with_errors).freeze

  # rubocop:disable Metrics/BlockLength
  included do
    chatop :failed_jobs,
           /failed[-_]jobs/,
           "failed-jobs --from YYYY-MM-DD HH:MM --to YYYY-MM-DD HH:MM " \
           "[--state timed_out|processed_with_errors] " \
           "(UpdateJob#created_at) - Report failed job metrics" do
      time_range = validate_time_range(jsonrpc_params)
      return unless time_range

      state = validate_state(jsonrpc_params["state"])
      return if jsonrpc_params["state"].present? && state.nil?

      start_time, end_time = time_range

      begin
        output = compute_failed_jobs_metrics(start_time, end_time, state: state)
        jsonrpc_success output
      rescue ActiveRecord::QueryCanceled, ActiveRecord::StatementTimeout, Trilogy::ProtocolError
        jsonrpc_failure "Query timed out - try a shorter time range"
      end
    end

    chatop :failed_repos,
           /failed[-_]repos/,
           "failed-repos --from YYYY-MM-DD HH:MM --to YYYY-MM-DD HH:MM " \
           "[--state timed_out|processed_with_errors] " \
           "(UpdateJob#created_at) - Report failed repos" do
      time_range = validate_time_range(jsonrpc_params)
      return unless time_range

      state = validate_state(jsonrpc_params["state"])
      return if jsonrpc_params["state"].present? && state.nil?

      start_time, end_time = time_range

      begin
        output = compute_failed_repos_metrics(start_time, end_time, state: state)
        jsonrpc_success output
      rescue ActiveRecord::QueryCanceled, ActiveRecord::StatementTimeout, Trilogy::ProtocolError
        jsonrpc_failure "Query timed out - try a shorter time range"
      end
    end

    chatop :failed_accounts,
           /failed[-_]accounts/,
           "failed-accounts --from YYYY-MM-DD HH:MM --to YYYY-MM-DD HH:MM " \
           "[--state timed_out|processed_with_errors] " \
           "(UpdateJob#created_at) - Report failed accounts" do
      time_range = validate_time_range(jsonrpc_params)
      return unless time_range

      state = validate_state(jsonrpc_params["state"])
      return if jsonrpc_params["state"].present? && state.nil?

      start_time, end_time = time_range

      begin
        output = compute_failed_accounts_metrics(start_time, end_time, state: state)
        jsonrpc_success output
      rescue ActiveRecord::QueryCanceled, ActiveRecord::StatementTimeout, Trilogy::ProtocolError
        jsonrpc_failure "Query timed out - try a shorter time range"
      end
    end

    chatop :failed_errors,
           /failed[-_]errors/,
           "failed-errors --from YYYY-MM-DD HH:MM --to YYYY-MM-DD HH:MM " \
           "--error-type ERROR_TYPE[,ERROR_TYPE2,...] " \
           "(UpdateJob#created_at) - Report jobs, repos, and accounts for specific error types" do
      time_range = validate_time_range(jsonrpc_params)
      return unless time_range

      error_types = parse_error_types(jsonrpc_params["error-type"])
      if error_types.blank?
        jsonrpc_failure "error-type is required"
        return
      end

      start_time, end_time = time_range

      begin
        output = compute_failed_errors_metrics(start_time, end_time, error_types: error_types)
        jsonrpc_success output
      rescue ActiveRecord::QueryCanceled, ActiveRecord::StatementTimeout, Trilogy::ProtocolError
        jsonrpc_failure "Query timed out - try a shorter time range"
      end
    end
  end
  # rubocop:enable Metrics/BlockLength

  private

  def validate_state(state)
    return nil if state.blank?

    normalized = state.to_s.strip.downcase.tr("-", "_").to_sym
    unless FAILED_STATES.include?(normalized)
      jsonrpc_failure "Invalid state: #{state}. " \
                      "Valid states: #{FAILED_STATES.join(', ')}"
      return nil
    end

    normalized
  end

  def validate_time_range(params)
    begin
      start_time = DateTime.parse(params[:from]).utc
      end_time = DateTime.parse(params[:to]).utc
    rescue ArgumentError, TypeError
      jsonrpc_failure "Invalid date format: from #{params[:from]}, to #{params[:to]}"
      return nil
    end

    if start_time > end_time
      jsonrpc_failure "Start time must be before or equal to end time: from #{start_time}, to #{end_time}"
      return nil
    end

    if start_time < 1.month.ago || end_time > Time.now.utc
      jsonrpc_failure "Date range must be in the last month: from #{start_time}, to #{end_time}"
      return nil
    end

    [start_time, end_time]
  end

  def failed_states(state)
    state ? [state] : FAILED_STATES
  end

  def parse_error_types(error_type_param)
    return nil if error_type_param.blank?

    # Split by comma and strip whitespace from each type
    error_type_param.to_s.split(",").map(&:strip).compact_blank
  end

  def compute_failed_jobs_metrics(start_time, end_time, state: nil)
    start_id, end_id = id_range_for_time_range(start_time, end_time)
    return "No update jobs found in the specified time range" unless start_id && end_id

    states = failed_states(state)
    lines = build_failed_jobs_summary(
      start_id: start_id, end_id: end_id, states: states,
      start_time: start_time, end_time: end_time, state: state
    )

    # Include error type breakdown when filtering by state
    lines.concat(build_error_breakdown_lines(start_id, end_id, states)) if state

    lines.join("\n")
  end

  def build_failed_jobs_summary(start_id:, end_id:, states:, start_time:, end_time:, state:)
    base_query = UpdateJob.where(id: start_id..end_id)
    counts_by_state = states.index_with { |s| base_query.in_state(s).count }
    total_failed = counts_by_state.values.sum
    failed_without_pr = base_query.in_state(*states).where.missing(:pull_requests).count

    filter_text = state ? " [state: #{state}]" : ""
    state_breakdown = counts_by_state.map { |k, v| "#{k}: #{v}" }.join(", ")

    [
      "Failed metrics (UpdateJob#created_at) from #{start_time.utc} to #{end_time.utc}#{filter_text}:",
      "total_failed_jobs: #{total_failed}",
      "failed_jobs_by_state: {#{state_breakdown}}",
      "failed_jobs_without_pr: #{failed_without_pr}",
    ]
  end

  def build_error_breakdown_lines(start_id, end_id, states)
    error_breakdown = compute_error_breakdown_for_jobs(start_id, end_id, states)
    lines = ["", "error_breakdown:"]

    error_breakdown.each do |error_type, count|
      category = UpdateJob::UpdateErrorClassification.error_category(error_type: error_type)
      lines << "  #{error_type}: #{count} (#{category})"
    end

    lines
  end

  def compute_error_breakdown_for_jobs(start_id, end_id, states)
    error_counts = Hash.new(0)

    ActiveRecord::Base.connected_to(role: :reading) do
      each_id_batch(start_id, end_id) do |batch_start, batch_end|
        batch_job_ids = UpdateJob.
                        where(id: batch_start..batch_end).
                        in_state(*states).
                        pluck(:id)

        next if batch_job_ids.empty?

        UpdateJobError.
          where(update_job_id: batch_job_ids).
          group(:error_type).
          count.
          each { |k, v| error_counts[k] += v }
      end
    end

    error_counts.sort_by { |_, v| -v }
  end

  def compute_failed_errors_metrics(start_time, end_time, error_types:)
    start_id, end_id = id_range_for_time_range(start_time, end_time)
    return "No update jobs found in the specified time range" unless start_id && end_id

    affected_ids = collect_failed_error_affected_ids(start_id, end_id, error_types)

    # For multiple error types, show all; for single error type, show category
    if error_types.size == 1
      category = UpdateJob::UpdateErrorClassification.error_category(error_type: error_types.first)
      format_failed_errors_metrics(start_time, end_time, error_types, category, affected_ids)
    else
      format_failed_errors_metrics(start_time, end_time, error_types, nil, affected_ids)
    end
  end

  def collect_failed_error_affected_ids(start_id, end_id, error_types)
    affected_ids = {
      job_ids: Set.new,
      repo_ids: Set.new,
      account_ids: Set.new,
    }

    ActiveRecord::Base.connected_to(role: :reading) do
      each_id_batch(start_id, end_id) do |batch_start, batch_end|
        collect_batch_ids(batch_start, batch_end, error_types: error_types, affected_ids: affected_ids)
      end
    end

    affected_ids
  end

  def collect_batch_ids(batch_start, batch_end, error_types:, affected_ids:)
    failed_job_ids = UpdateJob.where(id: batch_start..batch_end).in_state(*FAILED_STATES).pluck(:id)
    return if failed_job_ids.empty?

    batch_job_ids = UpdateJobError.
                    where(update_job_id: failed_job_ids, error_type: error_types).
                    distinct.
                    pluck(:update_job_id)
    return if batch_job_ids.empty?

    affected_ids[:job_ids].merge(batch_job_ids)
    collect_repo_and_account_ids(batch_job_ids, affected_ids)
  end

  def collect_repo_and_account_ids(job_ids, affected_ids)
    UpdateJob.
      where(id: job_ids).
      joins(update_config: :repo).
      pluck("repos.id", "repos.account_id").
      each do |repo_id, account_id|
        affected_ids[:repo_ids] << repo_id
        affected_ids[:account_ids] << account_id
      end
  end

  def format_failed_errors_metrics(start_time, end_time, error_types, category, affected_ids)
    error_list = error_types.join(", ")
    category_suffix = category ? " (#{category})" : ""
    "Failed errors (UpdateJob#created_at) from #{start_time.utc} to #{end_time.utc} " \
      "[error_type: #{error_list}]#{category_suffix}:\n" \
      "jobs_affected: #{affected_ids[:job_ids].size}\n" \
      "repos_affected: #{affected_ids[:repo_ids].size}\n" \
      "accounts_affected: #{affected_ids[:account_ids].size}"
  end

  def base_failed_jobs_query(start_id, end_id, state: nil)
    states = failed_states(state)
    UpdateJob.
      where(id: start_id..end_id).
      in_state(*states)
  end

  def compute_failed_repos_metrics(start_time, end_time, state: nil)
    start_id, end_id = id_range_for_time_range(start_time, end_time)
    return "No update jobs found in the specified time range" unless start_id && end_id

    repo_ids = Set.new

    each_id_batch(start_id, end_id) do |batch_start, batch_end|
      repo_ids.merge(
        base_failed_jobs_query(batch_start, batch_end, state: state).
          joins(update_config: :repo).
          distinct.
          pluck("repos.id")
      )
    end

    filter_text = state ? " [state: #{state}]" : ""
    "Failed repos (UpdateJob#created_at) from #{start_time.utc} to #{end_time.utc}#{filter_text}:\n" \
      "repos_affected: #{repo_ids.size}"
  end

  def compute_failed_accounts_metrics(start_time, end_time, state: nil)
    start_id, end_id = id_range_for_time_range(start_time, end_time)
    return "No update jobs found in the specified time range" unless start_id && end_id

    account_ids = Set.new

    each_id_batch(start_id, end_id) do |batch_start, batch_end|
      account_ids.merge(
        base_failed_jobs_query(batch_start, batch_end, state: state).
          joins(update_config: :repo).
          distinct.
          pluck("repos.account_id")
      )
    end

    filter_text = state ? " [state: #{state}]" : ""
    "Failed accounts (UpdateJob#created_at) from #{start_time.utc} to #{end_time.utc}#{filter_text}:\n" \
      "accounts_affected: #{account_ids.size}"
  end
end
