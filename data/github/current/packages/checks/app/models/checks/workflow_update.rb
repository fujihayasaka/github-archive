# typed: true
# frozen_string_literal: true

class Checks::WorkflowUpdate
  attr_reader :workflow_run_id

  WARNING_LEVEL_MAP = {
    LEVEL_UNKNOWN: nil,
    LEVEL_NOTICE: "notice",
    LEVEL_WARNING: "warning",
    LEVEL_FAILURE: "failure",
  }.freeze

  CHECK_SUITE_STATUS_MAP = {
    STATUS_UNKNOWN: nil,
    STATUS_PENDING: CheckSuite.statuses[:pending],
    STATUS_COMPLETED: CheckSuite.statuses[:completed],
  }.freeze

  CHECK_RUN_AND_CHECK_STEP_STATUS_MAP = {
    STATUS_UNKNOWN: nil,
    STATUS_NOT_STARTED: CheckRun.statuses[:queued],
    STATUS_IN_PROGRESS: CheckRun.statuses[:in_progress],
    STATUS_POSTPONED: CheckRun.statuses[:queued],
    STATUS_CANCELLING: CheckRun.statuses[:in_progress],
    STATUS_ALL: CheckRun.statuses[:in_progress],
    STATUS_COMPLETED: CheckRun.statuses[:completed],
    STATUS_PENDING: CheckRun.statuses[:pending],
  }.freeze

  CHECK_SUITE_CONCLUSION_MAP = {
    CONCLUSION_UNKNOWN: nil,
    CONCLUSION_SUCCEEDED: CheckSuite.conclusions[:success],
    CONCLUSION_FAILED: CheckSuite.conclusions[:failure],
    CONCLUSION_CANCELED: CheckSuite.conclusions[:cancelled],
    CONCLUSION_SKIPPED: CheckSuite.conclusions[:skipped],
  }.freeze

  CHECK_RUN_AND_CHECK_STEP_CONCLUSION_MAP = {
    RESULT_UNKNOWN: nil,
    RESULT_CANCELED: CheckStep.conclusions[:cancelled],
    RESULT_FAILED: CheckStep.conclusions[:failure],
    RESULT_PARTIALLY_SUCCEEDED: nil,
    RESULT_SUCCEEDED: CheckStep.conclusions[:success],
    RESULT_SKIPPED: CheckStep.conclusions[:skipped],
  }.freeze

  GATE_REQUEST_STATE_MAP = {
    STATE_OPEN: "open",
    STATE_CLOSED: "closed",
    STATE_REJECTED: "rejected",
    STATE_UNKNOWN: nil,
  }.freeze

  def initialize(event_data)
    @repository_global_id = event_data.fetch(:repository_id)
    @workflow_run_id = event_data.fetch(:workflow_run_id)

    @check_run_data = event_data[:job]
    @check_suite_data = event_data[:run]
    @gate_data = event_data[:gate]
  end

  def check_suite_update?
    @check_suite_data.present?
  end

  def check_run_update?
    @check_run_data.present?
  end

  def gate_update?
    @gate_data.present?
  end

  def update_type
    return :job if check_run_update?
    return :run if check_suite_update?
    return :gate if gate_update?

    :unknown
  end

  def check_suite_update_data
    {
      annotations: annotations,
      artifacts: artifacts,
      concurrency: concurrency,
      conclusion: CHECK_SUITE_CONCLUSION_MAP[@check_suite_data[:conclusion]],
      check_suite_updates: {
        status: CHECK_SUITE_STATUS_MAP[@check_suite_data[:status]],
        completed_log_url: @check_suite_data.dig(:completed_log, :url),
      }
    }
  end

  def check_run_update_data
    {
      annotations: annotations,
      concurrency: concurrency,
      check_run_updates: check_run_updates,
      check_run_steps: check_run_steps,
      deployment_environments: deployment_environments,
      workflow_job_run: workflow_job_run,
      is_cloned_from_previous_run: @check_run_data.fetch(:is_cloned_from_previous_run, false)
    }
  end

  def gate_request_update_data
    {
      gate_id: global_id_to_local_id(@gate_data[:gate_id]),
      check_run_id: global_id_to_local_id(@gate_data[:check_run_id]),
      gate_state: GATE_REQUEST_STATE_MAP[@gate_data[:state]],
      expires_at: parse_time(@gate_data[:expires_at]),
      concluded: @gate_data[:concluded],
      token: @gate_data[:token],
    }
  end

  def repository_id
    @repository_id ||= global_id_to_local_id(@repository_global_id)
  end

  def check_suite_id
    return global_id_to_local_id(@check_suite_data[:check_suite_id]) if @check_suite_data.present?

    nil
  end

  def check_run_id
    return global_id_to_local_id(@check_run_data[:check_run_id]) if @check_run_data.present?
    return global_id_to_local_id(@gate_data[:check_run_id]) if @gate_data.present?

    nil
  end

  private

  def deployment_environments
    @deployment_environments ||= {
      name: @check_run_data&.dig(:environment, :name),
      url: @check_run_data&.dig(:environment, :url)
    }
  end

  def check_run_updates
    return @check_run_updates if defined?(@check_run_updates)

    cloned = @check_run_data.fetch(:is_cloned_from_previous_run, false)

    @check_run_updates = {
      external_id: @check_run_data[:external_id],
      display_name: check_run_display_name,
      status: check_run_status,
      number: @check_run_data[:number],
      conclusion: check_run_conclusion,
      completed_at: check_run_completed_at,
      started_at: check_run_started_at,
    }.compact

    # Make sure we don't accidentally overwrite existing values for cloned runs
    # ADR: https://github.com/github/c2c-actions/blob/main/docs/adrs/3797-logs-and-artifacts-for-partial-reruns.md
    if @check_run_data&.dig(:complete, :log).present? && !cloned
      @check_run_updates[:completed_log_url] = @check_run_data&.dig(:complete, :log, :url)
      @check_run_updates[:completed_log_lines] = @check_run_data&.dig(:complete, :log, :lines)
    end

    if @check_run_data&.dig(:in_progress, :log_stream).present?
      @check_run_updates[:streaming_log_url] = @check_run_data&.dig(:in_progress, :log_stream, :url)
    end

    @check_run_updates
  end

  def workflow_job_run
    @workflow_job_run ||= {
      job_key: @check_run_data[:job_key],
      parent_job_id: @check_run_data[:parent_job_id],
      runner_id: @check_run_data[:runner_id],
      runner_name: @check_run_data[:runner_name],
      runner_group_id: @check_run_data[:runner_group_id],
      runner_group_name: @check_run_data[:runner_group_name],
      label_data: @check_run_data[:labels],
      summary_url: @check_run_data&.dig(:complete, :summary, :url),
    }.compact
  end

  def gate_concluded?
    return nil if @gate_data.nil?

    @gate_data[:concluded]
  end

  def check_run_steps
    return nil if @check_run_data.nil?

    @check_run_steps ||= begin
      @check_run_data[:steps]&.map do |step_data|
        check_step_status_data = check_run_step_status(step: step_data)

        {
          number: step_data[:number],
          external_id: step_data[:external_id],
          name: step_data[:name],
        }.merge(check_step_status_data)
      end
    end
  end

  def check_run_display_name
    return nil if @check_run_data.nil?

    @check_run_data[:display_name]
  end

  def check_run_status
    return nil if @check_run_data.nil?

    return CHECK_RUN_AND_CHECK_STEP_STATUS_MAP[:STATUS_COMPLETED] if @check_run_data[:complete].present?

    return CheckRun.statuses[:completed] if @check_run_data[:conclusion].present?

    status = @check_run_data.dig(:in_progress, :status)

    CHECK_RUN_AND_CHECK_STEP_STATUS_MAP[status]
  end

  def concurrency
    concurrency = @check_run_data&.dig(:concurrency) || @check_suite_data&.dig(:concurrency)

    return nil if concurrency.nil?

    if concurrency[:waiting_on_resource].present?
      waiting_on_resource = concurrency[:waiting_on_resource]
      check_run_global_id = waiting_on_resource[:check_run_global_id]
      check_suite_global_id = waiting_on_resource[:check_suite_global_id]

      if check_run_global_id.present?
        waiting_on_resource[:check_run_id] = global_id_to_local_id(check_run_global_id)
      end

      if check_suite_global_id.present?
        waiting_on_resource[:check_suite_id] = global_id_to_local_id(check_suite_global_id)
      end
    end

    concurrency
  end

  def annotations
    annotations = @check_run_data&.dig(:annotations) || @check_suite_data&.dig(:annotations)

    return [] if annotations.nil?

    annotations.map do |annotation|
      annotation_level = annotation[:annotation_level]
      warning_level = WARNING_LEVEL_MAP[annotation_level]

      {
        warning_level: warning_level,
        message: annotation[:message],
        raw_details: annotation[:raw_details],
        filename: annotation[:file_path],
        start_line: parse_annotation_line(annotation[:start_line]),
        end_line: parse_annotation_line(annotation[:end_line]),
        start_column: parse_annotation_line(annotation[:start_column]),
        end_column: parse_annotation_line(annotation[:end_column]),
        step_number: parse_annotation_line(annotation[:step_number]),
        title: annotation[:title],
        repository_id: repository_id,
      }.compact
    end
  end

  def parse_annotation_line(line)
    return nil if line == 0 || line == "0"

    line
  end

  def artifacts
    return nil if @check_suite_data.nil?

    @artifacts ||= @check_suite_data[:artifacts]&.map do |artifact|
      {
        repository_id: repository_id,
        source_url: artifact[:url],
        name: artifact[:name],
        size: artifact[:size],
        created_at: parse_time(artifact[:created_at]),
        expires_at: parse_time(artifact[:expires_at]),
      }
    end
  end

  def check_run_conclusion
    return nil if @check_run_data&.dig(:complete, :result).nil?

    raw_result = @check_run_data[:complete][:result]

    CHECK_RUN_AND_CHECK_STEP_CONCLUSION_MAP[raw_result]
  end

  def check_run_completed_at
    return nil if @check_run_data&.dig(:complete, :result).nil?

    parse_time(@check_run_data[:complete][:completed_at])
  end

  def check_run_started_at
    if @check_run_data[:complete].present?
      return parse_time(@check_run_data[:complete][:started_at])
    end

    if @check_run_data[:in_progress].present?
      return parse_time(@check_run_data[:in_progress][:started_at])
    end

    nil
  end

  def parse_time(time)
    return nil if time.blank?

    Google::Protobuf::Timestamp.new(time).to_time
  end

  def check_run_step_status(step:)
    if step[:in_progress].present?
      return {
        status: CheckStep.statuses[:in_progress],
        started_at: parse_time(step[:in_progress][:started_at]),
      }
    end

    if step[:complete].present?
      complete_data = step[:complete]

      step_data = {
        status: CheckStep.statuses[:completed],
        completed_at: parse_time(complete_data[:completed_at]),
        started_at: parse_time(complete_data[:started_at]),
        conclusion: CHECK_RUN_AND_CHECK_STEP_CONCLUSION_MAP[complete_data[:result]],
      }

      if complete_data[:log]
        step_data[:completed_log] = {
          url: complete_data.dig(:log, :url),
          lines: complete_data.dig(:log, :lines),
        }
      end

      return step_data
    end

    { status: CheckStep.statuses[:queued] }
  end

  def global_id_to_local_id(global_id)
    Platform::Helpers::GlobalId.parse(global_id).id.to_i
  end
end
