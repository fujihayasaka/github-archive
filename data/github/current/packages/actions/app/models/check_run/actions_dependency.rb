# typed: false
# frozen_string_literal: true

# Actions-specific functionality for check runs (AKA workflow job runs)

module CheckRun::ActionsDependency
  STATUSES_WITHOUT_STEPS = %w[requested queued waiting pending].freeze
  CONCLUSIONS_WITHOUT_STEPS = %w[skipped].freeze

  HTTP_ERRORS = [
    Faraday::ConnectionFailed,
    URI::InvalidURIError,
    Timeout::Error,
    Errno::EINVAL,
    Errno::ECONNRESET,
    SocketError,
    JSON::ParserError,
  ]

  MAX_LOGS_RETENTION_PERIOD = 400

  def async_steps_from_backend(change_id = 0)
    Promise.all([self.async_check_suite, self.async_workflow_job_run]).then do |check_suite, workflow_job_run|
      if workflow_job_run
        Promise.all([check_suite.async_workflow_run, workflow_job_run.async_workflow_run_execution]).then do
          steps_from_backend(change_id)
        end
      else
        []
      end
    end
  end

  def async_passthrough_steps?
    Promise.all([self.async_check_suite, self.async_workflow_job_run]).then do |check_suite, workflow_job_run|
      if workflow_job_run
        Promise.all([check_suite.async_workflow_run, workflow_job_run.async_workflow_run_execution]).then do
          passthrough_steps?
        end
      else
        false
      end
    end
  end

  def check_run_has_steps?
    return false if STATUSES_WITHOUT_STEPS.include? status
    return false if CONCLUSIONS_WITHOUT_STEPS.include? conclusion
    true
  end

  def steps_from_backend(change_id = 0)
    return [] unless check_run_has_steps?

    if steps_via_results_service?
      steps_from_results(change_id)
    else
      steps_from_launch(change_id)
    end
  end

  # When a check run is in progress, we want the step data directly from actions
  # service (via launch). A change_id of 0 will always have the latest information
  def steps_from_launch(change_id = 0)
    # Fixes: https://github.com/github/c2c-actions-checks/issues/144
    # Users can create check runs on check suites created by actions, this guard
    # prevents a grpc call for non-actions check runs, which would always fail.
    # Long term solution: https://github.com/github/c2c-actions-checks/issues/9
    return [] unless is_actions_check_run?

    resp = Launch::Twirp.checks_client(lab: !!check_suite.lab_workflow?).steps_for_change_id(
      repository: repository,
      change_id: change_id,
      job_id: external_id,
      plan_id: check_suite.external_id
      # https://github.com/github/c2c-actions/blob/main/docs/actions-ids.md
    )

    return [] unless resp.value&.steps

    new_steps = resp.value.steps.map do |step|
      started_at = Time.at(step.started_at.seconds) if step.started_at
      completed_at = Time.at(step.completed_at.seconds) if step.completed_at

      CheckStep.new(
        check_run_id:        id,
        name:                step.name,
        status:              step.status,
        conclusion:          step.conclusion,
        started_at:          started_at,
        completed_at:        completed_at,
        number:              step.number,
        external_id:         step.id,
        repository_id:       repository.id,
        completed_log_lines: step.log&.line_count,
        completed_log_url:   step.log&.url,
        change_id:           step.change_id
      )
    end
  end

  # Results service is the source of truth for steps of in-progress jobs.
  def steps_from_results(change_order = 0)
    return [] unless is_actions_check_run? && workflow_job_run
    return [] unless check_run_has_steps?

    # if the workflow job run is a clone, we want to get the steps from the original workflow run execution as results doesn't have the context to get the steps from the cloned workflow run execution.
    # this only applies to non-four nines actions as we have the required context to get the steps from the cloned workflow run execution for four nines actions
    workflow_run_id = if workflow_job_run.cloned_from_previous_run? && !check_suite.workflow_run&.is_actions_four_nines_run?
      workflow_job_run.original_workflow_run_execution.external_id
    else
      workflow_job_run.workflow_run_execution.external_id
    end

    result = ActionsResults::Twirp.steps_client.get_workflow_steps(
      workflow_run_backend_id: workflow_run_id,
      workflow_job_run_backend_id: external_id,
      change_order: change_order,
    )

    if !result.call_succeeded?
      GitHub.dogstats.increment("actions.workflow_job_run.steps_from_results", tags: ["status_code:#{result.status}"])
      GitHub.logger.error("failed to fetch steps from results service", {
        "gh.check_run.id" => id,
        "gh.actions.workflow_run.backend_id" => check_suite.external_id,
        "gh.actions.workflow_job_run.backend_id" => external_id,
        "gh.check_run.status" => status,
        "http.response.status_code" => result.status,
        "exception.message" => result.options[:message],
      })

      # FALLBACK: # if the check run is not concluded and the action is four nines, return an empty array since neither launch nor RAC will have steps
      return [] if !concluded? && check_suite.workflow_run&.is_actions_four_nines_run?

      # FALLBACK: if the check run is not concluded, and the action isn't four nines, fallback to steps in launch
      return steps_from_launch(change_order) if !concluded?

      # FALLBACK: if check run is concluded, fallback to steps in mysql
      return steps
    end

    result.value.steps.map do |step|
      CheckStep.from_results_step(
        step: step,
        repository_id: self.repository_id,
        check_run_id: self.id
      )
    end
  end

  def passthrough_steps?
    if completed_steps_via_results_service?
      return true
    end

    !concluded?
  end

  def disable_dotcom_check_steps_writes?
    !opt_out_from_results?
  end

  def opt_out_from_results?
    GitHub.enterprise? || GitHub.flipper[:actions_opt_out_results_service].enabled?(repository.owner) || GitHub.flipper[:actions_opt_out_results_service].enabled?(repository)
  end

  def steps_via_results_service?
    !opt_out_from_results? || check_suite.workflow_run&.is_actions_four_nines_run?
  end

  def streaming_logs_via_results?
    !opt_out_from_results? || check_suite.workflow_run&.is_actions_four_nines_run?
  end

  def system_logs_from_results?
    return false unless conclusion.nil?
    check_suite.workflow_run&.is_actions_four_nines_run?
  end

  def system_logs
    return nil unless system_logs_from_results?

    resp = ActionsResults::Twirp.log_client.get_step_log_scrollback(
      workflow_run_backend_id: check_suite.external_id,
      workflow_job_run_backend_id: external_id,
      workflow_step_backend_id: ActionsResults::Utils::SYSTEM_LOGS_KEY
    )

    return nil unless resp.call_succeeded?
    resp.value.lines.map(&:line).join("\n")
  end

  def completed_steps_via_results_service?
    (!GitHub.enterprise? && !opt_out_from_results? && created_at.year >= 2024) || check_suite.workflow_run&.is_actions_four_nines_run?
  end

  def register_job_for_live_logs_from_results
    resp = ActionsResults::Twirp.log_client.register_job_run_for_live_logs(
      workflow_run_backend_id: check_suite.external_id,
      workflow_job_run_backend_id: external_id
    )

    unless resp.call_succeeded?
      GitHub.dogstats.increment("actions.workflow_job_run.register_job_run_for_live_logs", tags: ["status_code:#{resp.status}"])
      GitHub.logger.error("failed to register live logs", {
        "gh.repo.id" => repository_id,
        "gh.check_run.id" => id,
        "gh.actions.workflow_run.backend_id" => check_suite.external_id,
        "gh.actions.workflow_job_run.backend_id" => external_id,
        "http.response.status_code" => resp.status,
        "exception.message" => resp.options[:message],
      })
    end
  end

  # Helper method to determine if a check run is created by Actions. Only Actions v2 checks have the `number` field set.
  # Also, Actions v2 that are used as a dummy check for presenting information don't have that field either
  def is_actions_check_run?
    number.present?
  end

  # Delegate the rerequest call over to the check_suite (see comments on that method)
  # but keep this as the entry point because it is check run specific
  def actions_rerequest(actor:, enable_debug_logging: false)
    check_suite.rerequest(actor: actor, only_check_run_id: id, enable_debug_logging: enable_debug_logging)
  end

  # "github-actions" is the external_id that is set from launch when the launch build healer runs attempting to fix
  # this check run in some way. It's artificial, not a real UUID, and does not map to a plan in actions service.
  def actions_rerequestable?
    is_actions_check_run? && external_id.present? && external_id != "github-actions"
  end

  # Logs are only available for actions check runs
  def expired_logs?
    # Check expiry based on query param on completed_log_url
    return false unless completed_log_url

    # in progress job is never expired
    return false unless check_suite.completed_at

    parsed_log_url = URI.parse(completed_log_url)
    queries = Rack::Utils.parse_query parsed_log_url.query

    # For older logs that do not have `retention` set in query param, fallback to 400 days check
    return created_at + MAX_LOGS_RETENTION_PERIOD.days < Time.zone.now unless queries["retention"]

    check_suite.completed_at + queries["retention"].to_i.days < Time.zone.now
  end

  # In some instances the job start_time can come after the end_time due to timing issues with postbacks and sql
  # Visual only change to not display 0 or negative runtime durations as part of https://github.com/github/c2c-actions-checks/issues/572
  def actions_runtime_duration
    runtime_duration = duration
    if runtime_duration <= 0 && (conclusion == "success" || conclusion == "failure" || conclusion == "cancelled")
      runtime_duration = 1
    end
    runtime_duration
  end

  # 4 levels of nested reusable workflows are supported but in certain parts of the UI we don't wan't to display the full name such as "A / B / C / D / E" and instead just "E" with "A" being the parent
  # Returns 2 values, the parent job name and the shortened child job name
  def reusable_workflow_display_names
    return nil unless visible_name.include?(" / ")

    split_result = visible_name.split(" / ")
    [split_result.first, split_result.last]
  end

  def force_cancel_eligible_from_stafftools?
    return false unless is_actions_check_run?
    return false unless status == "in_progress" || status == "queued"
    # this is the hosted runner maximum job lifetime
    updated_at < 6.hours.ago
  end

  def force_cancel_from_stafftools
    attributes = { conclusion: "cancelled", status: "completed", completed_at: Time.zone.now }
    update(attributes)
  end
end
