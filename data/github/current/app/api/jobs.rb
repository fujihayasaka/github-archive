# typed: true
# frozen_string_literal: true

class Api::Jobs < Api::App
  include ActionsHelper

  ALLOWED_FILTER_PARAMS = %w[latest all]

  # Get all jobs for a run.
  get "/repositories/:repository_id/actions/runs/:run_id/jobs", operation_id: "actions/list-jobs-for-workflow-run" do
    repo = find_repo!

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    workflow_run = Actions::WorkflowRun.find_by(id: params[:run_id])
    deliver_error!(404) unless workflow_run
    deliver_error!(404) unless workflow_run.check_suite

    deliver_error!(404) unless repo.id == workflow_run.check_suite&.repository_id

    filter = params[:filter]
    filter = "latest" unless ALLOWED_FILTER_PARAMS.include?(filter)

    jobs = filter == "latest" ? workflow_run.latest_jobs : workflow_run.jobs
    jobs = paginate_rel(jobs)

    deliver :jobs_hash, { jobs: jobs, total_count: jobs.where(repository_id: repo.id).total_entries, repository_id: repo.id, workflow_run: workflow_run }
  end

  # Get all jobs for a specific attempt of a run.
  get "/repositories/:repository_id/actions/runs/:run_id/attempts/:attempt_number/jobs", operation_id: "actions/list-jobs-for-workflow-run-attempt" do
    repo = find_repo!

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    workflow_run = Actions::WorkflowRun.find_by(id: params[:run_id], repository_id: repo.id)
    deliver_error!(404) unless workflow_run
    deliver_error!(404) unless workflow_run.check_suite

    workflow_run_execution = workflow_run.workflow_run_executions.find { |execution| execution.attempt == params[:attempt_number].to_i }
    record_or_404(workflow_run_execution)

    jobs = workflow_run.latest_check_runs(execution: workflow_run_execution)
    jobs = paginate_rel(jobs)

    deliver :jobs_hash, { jobs: jobs, total_count: jobs.where(repository_id: repo.id).total_entries, repository_id: repo.id, workflow_run: workflow_run }
  end

  # Get a single job.
  get "/repositories/:repository_id/actions/jobs/:job_id", operation_id: "actions/get-job-for-workflow-run" do
    repo = find_repo!

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    job = find_job!(repo)

    deliver :job_hash, { job: job }
  end

  # Get logs for a job
  get "/repositories/:repository_id/actions/jobs/:job_id/logs", operation_id: "actions/download-job-logs-for-workflow-run" do
    repo = find_repo!

    control_access :read_actions_downloads,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?

    job = find_job!(repo)
    deliver_error!(404) unless job

    deliver_error!(410) if job.expired_logs?

    if GitHub.flipper[:actions_results_logs_api_fallback].enabled?(repo) || GitHub.flipper[:actions_results_logs_api_fallback].enabled?(repo.owner)
      completed_log_url = job.get_signed_completed_log_url
      deliver_error!(404) unless completed_log_url

      redirect completed_log_url
    else
      if ActionsResults::Utils.is_results_url?(job.completed_log_url) && job.check_suite&.workflow_run&.logs_via_results_service?
        deliver_error!(500) unless job.external_id.present? && job.check_suite.external_id.present?

        matches = ActionsResults::Utils.get_ids_from_results_url(job.completed_log_url)
        deliver_error! 500, message: "Failed to generate URL to download logs" unless matches.present?

        result = ActionsResults::Twirp.log_client.get_completed_job_log_url(
          workflow_job_run_backend_id: T.must(matches[:workflow_job_run_backend_id]),
          workflow_run_backend_id: T.must(matches[:workflow_run_backend_id]),
        )

        unless result.call_succeeded? && result.value.log_url.present?
          deliver_error! 500, message: "Failed to generate URL to download logs"
        end

        redirect result.value.log_url
      else
        completed_log_url = parse_completed_log_url(job.completed_log_url)
        deliver_error!(404) unless completed_log_url

        request = GitHub::Launch::Services::Artifactsexchange::ExchangeURLRequest.new({
          unauthenticated_url: completed_log_url,
          repository_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: get_global_id(repo)),
          resource_type: GitHub::Launch::Services::Artifactsexchange::ResourceType::TYPE_COMPLETED_JOB_LOG,
        })

        result = Launch::Twirp.artifacts_exchange_client_for_check_suite(job.check_suite).exchange_url(request)

        if result.call_succeeded?
          redirect result.value.authenticated_url
        else
          deliver_error! 500, message: "Failed to generate URL to download logs"
        end
      end
    end
  end

  # Create a re-run of a job
  post  "/repositories/:repository_id/actions/jobs/:job_id/rerun", operation_id: "actions/re-run-job-for-workflow-run" do
    repo = find_repo!

    control_access :write_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    check_run = find_job!(repo)

    workflow_run = check_run.check_suite&.workflow_run
    record_or_404(workflow_run)
    deliver_error!(404) if user_hidden?(workflow_run)

    data = receive_with_openapi
    enable_debug_logging = data["enable_debug_logging"] || false

    begin
      check_run.actions_rerequest(actor: current_user, enable_debug_logging: enable_debug_logging)
      deliver_empty status: 201
    rescue CheckSuite::ActionsDependency::ExpiredWorkflowRunError
      deliver_error! 403, message: "Unable to re-run this job because the workflow run was created over a month ago"
    rescue CheckSuite::AlreadyRerunningError
      deliver_error! 403, message: "The workflow run containing this job is already running"
    rescue CheckSuite::DisabledWorkflowError
      deliver_error! 403, message: "Unable to re-run this job, disabled workflow"
    rescue CheckSuite::ActionsDependency::PreviousJobAttemptError
      deliver_error! 403, message: "Only jobs from the current attempt can be re-run"
    rescue CheckSuite::NotRerequestableError
      deliver_error! 403, message: "Jobs in this workflow run cannot be re-run"
    end
  end


  private

  # The Results Service generats URLS that are of the form:
  # results://actions-results/run/<workflow run ID>/job/<workflow job run ID>?actions_url=<actions_url>.
  # We therefore, need to parse out the value of the query parameter as we plan on using the actions_url
  # for the foreseeable future.
  def parse_completed_log_url(url)
    return nil if url.blank?

    if ActionsResults::Utils.is_results_url?(url)
      return ActionsResults::Utils.actions_url(url)
    end

    url
  end

  def find_job!(repository)
    job = Checks.domain.check_runs.unsafe_for_id(params[:job_id].to_i) if params[:job_id]

    deliver_error! 404 unless job&.check_suite&.workflow_run
    deliver_error! 404 unless repository.id == job&.check_suite&.repository_id

    job
  end

  def user_hidden?(workflow_run)
    return false if current_user&.site_admin
    workflow_run.user_hidden
  end
end
