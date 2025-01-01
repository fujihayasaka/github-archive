# typed: false
# frozen_string_literal: true

class Api::WorkflowRuns < Api::App
  include ReceiveSchemaWithOpenApi
  include ActionsHelper

  # Get all runs for a regular-workflow, not a required-workflow
  get "/repositories/:repository_id/actions/workflows/:workflow_id/runs", operation_id: "actions/list-workflow-runs" do
    repo = find_repo!

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?

    workflow = repo.workflows.non_required.find_from_id_or_filename(params[:workflow_id])

    deliver_error! 404 unless workflow

    should_hide_spammy = !current_user&.site_admin?

    deliver_error! 404 if should_hide_spammy && workflow.spammy?

    deliver_error! 400, message: "invalid check_suite_id `#{params[:check_suite_id]}`" if check_suite_id_param_invalid?

    query = es_query
    if !query.empty?
      result = Actions::WorkflowRun.search(
        query: query,
        repo: repo,
        workflow_id: workflow.id,
        current_user: current_user,
        remote_ip: remote_ip,
        page: current_page,
        per_page: per_page,
        hide_spammy_runs: should_hide_spammy,
      )
      workflow_runs = result[:workflow_runs]
      total_count = result[:total_count]

      GitHub::PrefillAssociations.prefill_associations(workflow_runs, [:repository, { check_suite: :github_app }])
      deliver :workflow_runs_hash, { workflow_runs: workflow_runs, total_count: total_count }, { exclude_pull_requests: params[:exclude_pull_requests] }
    else
      pagination_scope = workflow.workflow_runs.most_recent

      if should_hide_spammy
        pagination_scope = pagination_scope.
          from("#{Actions::WorkflowRun.table_name} use index(index_workflow_runs_on_workflow_id_repository_id_user_hidden)").
          where(user_hidden: false)
      end

      pagination_scope = pagination_scope.where(repository_id: repo.id)
      paginated_scope = paginate_rel(pagination_scope)
      # Pre-compute `total_entries` so we have an apples-to-apples comparison in the experiment
      paginated_scope.total_entries

      workflow_runs = Scientist.run "workflow-runs-api-pagination" do |e|
        e.compare_ordered_records

        e.use do
          paginated_scope.load
        end

        e.try do
          scope = repo.workflow_runs.where("`workflow_runs`.`id` IN (SELECT * FROM (?) subquery_for_limit)", paginated_scope.reselect(:id)).order(paginated_scope.order_values)
          scope = scope.extending(WillPaginate::ActiveRecord::RelationMethods)
          scope = scope.per_page(paginated_scope.per_page)
          scope.current_page = paginated_scope.current_page
          scope.total_entries = paginated_scope.total_entries

          scope.load
        end
      end

      GitHub::PrefillAssociations.prefill_associations(workflow_runs, [:repository, { check_suite: :github_app }])
      deliver :workflow_runs_hash, { workflow_runs: workflow_runs, total_count: workflow_runs.total_entries }, { exclude_pull_requests: params[:exclude_pull_requests] }
    end
  end

  # Get all workflow runs for a repository, both regular and required
  get "/repositories/:repository_id/actions/runs", operation_id: "actions/list-workflow-runs-for-repo" do
    repo = find_repo!

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?

    should_hide_spammy = !current_user&.site_admin?

    deliver_error! 400, message: "invalid check_suite_id `#{params[:check_suite_id]}`" if check_suite_id_param_invalid?

    query = es_query
    if !query.empty?
      result = Actions::WorkflowRun.search(
        query: query,
        repo: repo,
        current_user: current_user,
        remote_ip: remote_ip,
        page: current_page,
        per_page: per_page,
        hide_spammy_runs: should_hide_spammy,
      )
      workflow_runs = result[:workflow_runs]
      total_count = result[:total_count]

      GitHub::PrefillAssociations.prefill_associations(workflow_runs, [:repository, { check_suite: :github_app }])
      deliver :workflow_runs_hash, { workflow_runs: workflow_runs, total_count: total_count }, { exclude_pull_requests: params[:exclude_pull_requests] }
    else
      pagination_scope = repo.workflow_runs.
        from("#{Actions::WorkflowRun.table_name} use index(index_workflow_runs_on_repository_id_user_hidden_imposer_repo_id)").
        most_recent

      if should_hide_spammy
        pagination_scope = pagination_scope.where(user_hidden: false)
      end

      paginated_scope = paginate_rel(pagination_scope)
      scope = repo.workflow_runs.where("`workflow_runs`.`id` IN (SELECT * FROM (?) subquery_for_limit)", paginated_scope.reselect(:id)).order(paginated_scope.order_values)
      scope = scope.extending(WillPaginate::ActiveRecord::RelationMethods)
      scope = scope.per_page(paginated_scope.per_page)
      scope.current_page = paginated_scope.current_page
      scope.total_entries = paginated_scope.total_entries

      workflow_runs = scope.load

      GitHub::PrefillAssociations.prefill_associations(workflow_runs, [:repository, :workflow, { check_suite: :github_app }])

      deliver :workflow_runs_hash, { workflow_runs: workflow_runs, total_count: workflow_runs.total_entries }, { exclude_pull_requests: params[:exclude_pull_requests] }
    end
  end

  get "/repositories/:repository_id/actions/required_workflows/:required_workflow_id/runs", operation_id: "actions/list-required-workflow-runs" do
    repo = find_repo!

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?

    required_workflow = repo.workflows.find_by(id: params[:required_workflow_id])
    deliver_error! 404 unless required_workflow
    deliver_error! 404 unless required_workflow.required?

    should_hide_spammy = !current_user&.site_admin?

    deliver_error! 404 if should_hide_spammy && required_workflow.spammy?

    deliver_error! 400, message: "invalid check_suite_id `#{params[:check_suite_id]}`" if check_suite_id_param_invalid?

    query = es_query
    if !query.empty?
      result = Actions::WorkflowRun.search(
        query: query,
        repo: repo,
        workflow_id: required_workflow.id,
        current_user: current_user,
        remote_ip: remote_ip,
        page: current_page,
        per_page: per_page,
        hide_spammy_runs: should_hide_spammy,
      )
      workflow_runs = result[:workflow_runs]
      total_count = result[:total_count]

      GitHub::PrefillAssociations.prefill_associations(workflow_runs, [:repository, { check_suite: :github_app }])
      deliver :workflow_runs_hash, { workflow_runs: workflow_runs, total_count: total_count }, { exclude_pull_requests: params[:exclude_pull_requests] }
    else
      pagination_scope = required_workflow.workflow_runs.most_recent

      if should_hide_spammy
        pagination_scope = pagination_scope.
          from("#{Actions::WorkflowRun.table_name} use index(index_workflow_runs_on_workflow_id_repository_id_user_hidden)").
          where(user_hidden: false)
      end

      paginated_scope = paginate_rel(pagination_scope)
      # Pre-compute `total_entries` so we have an apples-to-apples comparison in the experiment
      paginated_scope.total_entries

      workflow_runs = Scientist.run "required-workflow-runs-api-pagination" do |e|
        e.compare_ordered_records

        e.use do
          paginated_scope.load
        end

        e.try do
          scope = repo.workflow_runs.where("`workflow_runs`.`id` IN (SELECT * FROM (?) subquery_for_limit)", paginated_scope.reselect(:id)).order(paginated_scope.order_values)
          scope = scope.extending(WillPaginate::ActiveRecord::RelationMethods)
          scope = scope.per_page(paginated_scope.per_page)
          scope.current_page = paginated_scope.current_page
          scope.total_entries = paginated_scope.total_entries

          scope.load
        end
      end

      GitHub::PrefillAssociations.prefill_associations(workflow_runs, [:repository, { check_suite: :github_app }])
      deliver :workflow_runs_hash, { workflow_runs: workflow_runs, total_count: workflow_runs.total_entries }, { exclude_pull_requests: params[:exclude_pull_requests] }
    end
  end

  # Get a workflow run by (database) id
  get "/repositories/:repository_id/actions/runs/:run_id", operation_id: "actions/get-workflow-run" do
    repo = find_repo!

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?

    workflow_run = Actions::WorkflowRun.includes(:check_suite).find_by(id: params[:run_id], repository_id: repo.id)
    record_or_404(workflow_run)
    deliver_error!(404) if user_hidden?(workflow_run)
    deliver_error!(404) unless repo.id == workflow_run.check_suite.repository_id

    deliver :workflow_run_hash, workflow_run, { exclude_pull_requests: params[:exclude_pull_requests] }
  end

  # Get a workflow run attempt by (database) id and attempt number
  get "/repositories/:repository_id/actions/runs/:run_id/attempts/:attempt_number", operation_id: "actions/get-workflow-run-attempt" do
    repo = find_repo!

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?

    workflow_run = Actions::WorkflowRun.includes(:check_suite).find_by(id: params[:run_id], repository_id: repo.id)

    record_or_404(workflow_run)
    deliver_error!(404) if user_hidden?(workflow_run)

    workflow_run_execution =
      Actions::WorkflowRunExecution
        .with_referenced_workflows
        .where(repository: workflow_run.repository, workflow_run_id: workflow_run.id)
        .find { |execution| execution.attempt == params[:attempt_number].to_i }
    record_or_404(workflow_run_execution)

    deliver :workflow_run_execution_hash, workflow_run_execution, { exclude_pull_requests: params[:exclude_pull_requests] }
  end

  # Get logs for a workflow run
  get "/repositories/:repository_id/actions/runs/:run_id/logs", operation_id: "actions/download-workflow-run-logs" do
    repo = find_repo!

    control_access :read_actions_downloads,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?

    workflow_run = Actions::WorkflowRun.find_by(id: params[:run_id], repository_id: repo.id)
    record_or_404(workflow_run)
    deliver_error!(404) if user_hidden?(workflow_run)

    log_url = workflow_run.latest_workflow_run_execution&.completed_log_url || workflow_run.check_suite.completed_log_url
    deliver_error!(404) unless log_url
    deliver_error!(410) if workflow_run.expired_logs?

    if ActionsResults::Utils.is_results_url?(log_url) && workflow_run.logs_via_results_service?
      workflow_run_backend_id = workflow_run.latest_workflow_run_execution&.external_id || workflow_run.check_suite&.external_id
      deliver_error!(404) if workflow_run_backend_id.nil?

      result = ActionsResults::Twirp.log_client.get_completed_run_log_archive(
        workflow_run_backend_id: workflow_run_backend_id
      )

      unless result.call_succeeded? && result.value.log_url.present?
        deliver_error! 500, message: "Failed to generate URL to download logs"
      end

      redirect result.value.log_url
    else
      request = GitHub::Launch::Services::Artifactsexchange::ExchangeURLRequest.new({
        unauthenticated_url: log_url,
        repository_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: get_global_id(repo)),
        resource_type: GitHub::Launch::Services::Artifactsexchange::ResourceType::TYPE_COMPLETED_RUN_LOG,
      })

      result = Launch::Twirp.artifacts_exchange_client_for_check_suite(workflow_run.check_suite).exchange_url(request)

      if result.call_succeeded?
        redirect result.value.authenticated_url
      else
        deliver_error! 500, message: "Failed to generate URL to download logs"
      end
    end
  end

  # Get logs for a specific attempt of a workflow run
  get "/repositories/:repository_id/actions/runs/:run_id/attempts/:attempt_number/logs", operation_id: "actions/download-workflow-run-attempt-logs" do
    repo = find_repo!

    control_access :read_actions_downloads,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?

    workflow_run = Actions::WorkflowRun.includes(:check_suite).find_by(id: params[:run_id], repository_id: repo.id)
    record_or_404(workflow_run)
    deliver_error!(404) if user_hidden?(workflow_run)
    deliver_error!(410) if workflow_run.expired_logs?

    workflow_run_execution = workflow_run.workflow_run_executions.find { |execution| execution.attempt == params[:attempt_number].to_i }
    record_or_404(workflow_run_execution)
    deliver_error!(404) unless workflow_run_execution.completed_log_url

    if ActionsResults::Utils.is_results_url?(workflow_run_execution.completed_log_url) && workflow_run.logs_via_results_service?
      workflow_run_backend_id = workflow_run_execution&.external_id
      deliver_error!(404) if workflow_run_backend_id.nil?

      result = ActionsResults::Twirp.log_client.get_completed_run_log_archive(
        workflow_run_backend_id: workflow_run_backend_id
      )

      unless result.call_succeeded? && result.value.log_url.present?
        deliver_error! 500, message: "Failed to generate URL to download logs"
      end

      redirect result.value.log_url
    else
      request = GitHub::Launch::Services::Artifactsexchange::ExchangeURLRequest.new({
        unauthenticated_url: workflow_run_execution.completed_log_url,
        repository_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: get_global_id(repo)),
        resource_type: GitHub::Launch::Services::Artifactsexchange::ResourceType::TYPE_COMPLETED_RUN_LOG,
      })

      result = Launch::Twirp.artifacts_exchange_client_for_check_suite(workflow_run.check_suite).exchange_url(request)

      if result.call_succeeded?
        redirect result.value.authenticated_url
      else
        deliver_error! 500, message: "Failed to generate URL to download logs"
      end
    end
  end

  # Delete logs for a workflow run.
  delete "/repositories/:repository_id/actions/runs/:run_id/logs", operation_id: "actions/delete-workflow-run-logs" do
    repo = find_repo!

    control_access :write_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    workflow_run = Actions::WorkflowRun.find_by(id: params[:run_id], repository_id: repo.id)
    record_or_404(workflow_run)
    deliver_error!(404) if user_hidden?(workflow_run)

    receive_with_schema("workflow-run", "delete-logs")

    begin
      workflow_run.delete_logs(actor: current_user)
      deliver_empty status: 204
    rescue RuntimeError
      deliver_error! 500, message: "Could not delete the logs from file storage"
    rescue Actions::WorkflowRun::NotDeleteableError
      deliver_error! 403, message: "Unable to delete logs while the workflow is running"
    end
  end

  # Deletes a workflow run.
  delete "/repositories/:repository_id/actions/runs/:run_id", operation_id: "actions/delete-workflow-run" do
    @route_owner = "@github/c2c-actions-experience"
    repo = find_repo!

    control_access :write_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    workflow_run = Actions::WorkflowRun.find_by(id: params[:run_id], repository_id: repo.id)
    record_or_404(workflow_run)
    deliver_error!(404) if user_hidden?(workflow_run)

    begin
      workflow = workflow_run.workflow
      workflow_run.hard_delete(actor: current_user)

      if workflow && workflow.required?
        workflow.delete if workflow.workflow_runs.empty?
      end

    rescue Actions::WorkflowRun::NotDeleteableError
      deliver_error! 403, message: "Could not delete the workflow run"
    end

    deliver_empty status: 204
  end

  # re-run an action_required run from a PR from a fork
  post "/repositories/:repository_id/actions/runs/:run_id/approve", operation_id: "actions/approve-workflow-run" do
    repo = find_repo!

    control_access :write_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    workflow_run = Actions::WorkflowRun.find_by(id: params[:run_id], repository_id: repo.id)
    record_or_404(workflow_run)
    deliver_error!(404) if user_hidden?(workflow_run)

    check_suite = workflow_run.check_suite
    unless check_suite.action_required?
      deliver_error! 403, message: "This workflow run is not waiting for approval"
    end

    unless is_fork_pr_run?(workflow_run)
      deliver_error! 403, message: "This run is not from a fork pull request"
    end

    begin
      check_suite.rerequest(actor: current_user, only_failed_check_suites: false)
      deliver_empty status: 201
    rescue CheckSuite::ActionsDependency::ExpiredWorkflowRunError
      deliver_error! 403, message: "Unable to approve and run this workflow run because it was created over a month ago"
    rescue CheckSuite::AlreadyRerunningError
      deliver_error! 403, message: "This workflow is already running"
    rescue CheckSuite::DisabledWorkflowError
      deliver_error! 403, message: "Unable to approve and run disabled workflow"
    rescue CheckSuite::NotRerequestableError
      deliver_error! 403, message: "This workflow run cannot be approved and run"
    end
  end

  # Create a re-run of a workflow run
  post "/repositories/:repository_id/actions/runs/:run_id/rerun", operation_id: "actions/re-run-workflow" do
    repo = find_repo!

    control_access :write_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi
    enable_debug_logging = data["enable_debug_logging"] || false

    retry_workflow(repo, enable_debug_logging: enable_debug_logging)
  end

  # Retry a workflow run
  # The endpoint is active for existing users but docs are unpublished to discourage new users
  post "/repositories/:repository_id/actions/runs/:run_id/retry", operation_id: "actions/retry-workflow" do
    repo = find_repo!

    control_access :write_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    receive_with_schema("workflow-run", "retry")
    retry_workflow(repo)
  end

  # Create a re-run of a workflow run, only re-runs the failed jobs
  post "/repositories/:repository_id/actions/runs/:run_id/rerun-failed-jobs", operation_id: "actions/re-run-workflow-failed-jobs" do
    repo = find_repo!

    control_access :write_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi
    enable_debug_logging = data["enable_debug_logging"] || false

    retry_workflow(repo, only_failed_check_runs: true, enable_debug_logging: enable_debug_logging)
  end

  # Cancel a workflow run
  post "/repositories/:repository_id/actions/runs/:run_id/cancel", operation_id: "actions/cancel-workflow-run" do
    repo = find_repo!

    control_access :write_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    workflow_run = Actions::WorkflowRun.find_by(id: params[:run_id], repository_id: repo.id)
    record_or_404(workflow_run)
    deliver_error!(404) if user_hidden?(workflow_run)

    receive_with_schema("workflow-run", "cancel")

    check_suite = workflow_run.check_suite

    if check_suite.completed?
      deliver_error! 409, message: "Cannot cancel a workflow run that is completed."
    end

    if workflow_run.processing_retry? && workflow_run.latest_workflow_run_execution
      deliver_error! 409, message: "Cannot cancel a workflow re-run that has not yet queued."
    end

    result = check_suite.cancel(actor: current_user)

    if result.call_succeeded?
      deliver_empty status: 202
    else
      deliver_error! 500, message: "Failed to cancel workflow run"
    end
  end

  # Force cancel a workflow run
  post "/repositories/:repository_id/actions/runs/:run_id/force-cancel", operation_id: "actions/force-cancel-workflow-run" do
    repo = find_repo!

    control_access :write_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    workflow_run = Actions::WorkflowRun.find_by(id: params[:run_id], repository_id: repo.id)
    record_or_404(workflow_run)
    deliver_error!(404) if user_hidden?(workflow_run)

    receive_with_schema("workflow-run", "cancel")

    check_suite = workflow_run.check_suite

    if check_suite.completed?
      deliver_error! 409, message: "Cannot cancel a workflow run that is completed."
    end

    if workflow_run.processing_retry? && workflow_run.latest_workflow_run_execution
      deliver_error! 409, message: "Cannot cancel a workflow re-run that has not yet queued."
    end

    result = check_suite.cancel(actor: current_user, force: true)

    if result.call_succeeded?
      deliver_empty status: 202
    else
      deliver_error! 500, message: "Failed to cancel workflow run"
    end
  end

  # Get the billable information for a workflow run
  get "/repositories/:repository_id/actions/runs/:run_id/timing", operation_id: "actions/get-workflow-run-usage" do
    deliver_error!(404) if GitHub.enterprise?

    repo = find_repo!

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?

    workflow_run = Actions::WorkflowRun.find_by(id: params[:run_id], repository_id: repo.id)
    record_or_404(workflow_run)
    deliver_error!(404) if user_hidden?(workflow_run)

    lines = workflow_run.billing_usage_line_items

    payload = { billable: {} }
    duration = workflow_run.duration
    payload[:run_duration_ms] = (duration * 1000).to_i if duration > 0

    check_runs = workflow_run.action_check_runs
    env_to_job_data_map = environment_to_job_data_map(workflow_run, check_runs, lines)

    env_to_job_data_map.map do |environment, job_data|
      payload[:billable][environment] = billing_timing_for_environment(job_data)
    end

    deliver_raw(payload)
  end

  get "/repositories/:repository_id/actions/runs/:run_id/approvals", operation_id: "actions/get-reviews-for-run" do
    repo = find_repo!
    deliver_error!(404) unless repo.can_use_environments_api?

    control_access(:read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?)

    workflow_run = Actions::WorkflowRun
                     .preload(check_suite: [:gate_approval_logs])
                     .find_by(id: params[:run_id], repository_id: repo.id)
    record_or_404(workflow_run)
    deliver_error!(404) if user_hidden?(workflow_run)

    # we need to filter out the gate approval logs (in case of reruns)
    execution = workflow_run.latest_workflow_run_execution
    gate_approval_logs = workflow_run.check_suite.gate_approval_logs_for_execution(execution: execution)
      .includes(:user, { gate_approvals: [{ gate_request: :gate }, :environment] }).to_a

    gate_request_id_set = Set.new

    # find the latest gate approval log for each gate request
    filtered_gate_approval_logs = gate_approval_logs.sort_by(&:created_at).reverse.select do |approval_log|
      gate_request_ids = approval_log.gate_approvals&.pluck(:gate_request_id)
      if approval_log.state == "pending" && (gate_request_id_set.intersect? gate_request_ids)
        next false
      else
        gate_request_id_set |= gate_request_ids
        next true
      end
    end

    deliver(:gate_approval_logs_hash, gate_approval_logs: filtered_gate_approval_logs)

  end

  private

  # Returns a mapping of environment to job data, { duration_in_milliseconds: integer, check_run_id: integer }
  def environment_to_job_data_map(workflow_run, check_runs, line_items)
    check_run_id_to_line_item_map = workflow_run.billing_usage_line_items.group_by do
      |line_item| line_item.check_run_id
    end
    env_to_job_data_map = Hash.new { |hash, env| hash[env] = [] }

    check_runs.map do |check_run|
      line_item_list = check_run_id_to_line_item_map[check_run.id]
      if line_item_list.nil?
        runtime_env_from_check_run = check_run&.workflow_job_run&.label_data
        environment = check_run_label_data_to_environment(runtime_env_from_check_run)
        unless environment == "RUNTIME_UNKNOWN"
          env_to_job_data_map[environment] << { duration_in_milliseconds: 0, check_run_id: check_run.id }
        end
      else
        line_item_list.map  do |line_item|
          environment = line_item.job_runtime_environment
          env_to_job_data_map[environment] << {
            duration_in_milliseconds: line_item.duration_in_minutes.minutes.in_milliseconds.to_i,
            check_run_id: line_item.check_run_id
          }
        end
      end
    end

    env_to_job_data_map
  end

  def billing_timing_for_environment(job_data_list)
    milliseconds = job_data_list.sum do |job_data|
      job_data[:duration_in_milliseconds]
    end
    jobs = job_data_list.map { |job_data| job_data[:check_run_id] }.uniq.size
    job_runs = job_data_list.map do |job_data|
      {
        job_id: job_data[:check_run_id],
        duration_ms: job_data[:duration_in_milliseconds]
      }
    end
    { total_ms: milliseconds, jobs: jobs, job_runs: job_runs }
  end

  def es_query
    query = ""
    keys = [:actor, :branch, :head_sha, :event, :status, :created, :check_suite_id]
    keys.each do |key|
      field = key
      field = :is if key == :status
      query = "#{query} #{field}:\"#{params[key]}\"" if params[key]
    end
    query
  end

  def check_suite_id_param_invalid?
    params.has_key?(:check_suite_id) && !params[:check_suite_id].to_i.positive?
  end

  def is_fork_pr_run?(workflow_run)
    check_suite = workflow_run.check_suite
    workflow_run.trigger.is_a?(PullRequest) && check_suite.head_repository_id != workflow_run.repository_id
  end

  def user_hidden?(workflow_run)
    return false if current_user&.site_admin
    workflow_run.user_hidden
  end

  def retry_workflow(repo, only_failed_check_runs: false, enable_debug_logging: false)
    workflow_run = Actions::WorkflowRun.find_by(id: params[:run_id], repository_id: repo.id)
    record_or_404(workflow_run)
    deliver_error!(404) if user_hidden?(workflow_run)

    begin
      workflow_run.check_suite.rerequest(actor: current_user, only_failed_check_runs: only_failed_check_runs, only_failed_check_suites: false, enable_debug_logging: enable_debug_logging)
      deliver_empty status: 201
    rescue CheckSuite::ActionsDependency::ExpiredWorkflowRunError
      deliver_error! 403, message: "Unable to retry this workflow run because it was created over a month ago"
    rescue CheckSuite::AlreadyRerunningError
      deliver_error! 403, message: "This workflow is already running"
    rescue CheckSuite::DisabledWorkflowError
      deliver_error! 403, message: "Unable to retry disabled workflow"
    rescue CheckSuite::NotRerequestableError
      deliver_error! 403, message: "This workflow run cannot be retried"
    end
  end
end
