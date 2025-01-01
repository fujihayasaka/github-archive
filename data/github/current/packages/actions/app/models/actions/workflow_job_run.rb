# typed: true
# frozen_string_literal: true

# TODO:
# Our goal is to settle on the name "WorkflowJob" for parity with naming of
# the "workflow_job" webhook. [0]
# See this migration [1] for more context on why the table still needs to be
# named `workflow_job_runs`.
#
# [0]: app/models/hook/event/workflow_job_event.rb
# [1]: db/migrate/20201028154830_rename_workflow_jobs.rb

class Actions::WorkflowJobRun < ApplicationRecord::Domain::RepositoriesActionsChecks
  include GitHub::WorkflowConcurrency
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  belongs_to :workflow_run
  belongs_to :check_run, -> (workflow_job_run) { includes(:gate_requests).where(repository_id: workflow_job_run.repository_id) }, inverse_of: :workflow_job_run
  belongs_to :workflow_run_execution, -> (workflow_job_run) { where(repository_id: workflow_job_run.repository_id) }, inverse_of: :workflow_job_runs
  belongs_to :original_workflow_run_execution, -> (workflow_job_run) { where(repository_id: workflow_job_run.repository_id) }, class_name: "Actions::WorkflowRunExecution"

  validate :matches_workflow_run_repository
  validate :matches_check_run_repository

  delegate :actions_rerequestable?, to: :check_run

  ACTIONS_RESULTS_URI_SCHEME = "results"
  HTTP_ERRORS = [
    Faraday::ConnectionFailed,
    URI::InvalidURIError,
    Timeout::Error,
    Errno::EINVAL,
    Errno::ECONNRESET,
    SocketError,
    JSON::ParserError,
  ]

  def channel
    GitHub::WebSocket::Channels.workflow_job_run(workflow_run_id, parent_job_id)
  end

  def actions_results_channel
    GitHub::WebSocket::Channels.actions_results_channel(workflow_run_execution&.external_id, check_run&.external_id)
  end

  def get_blocking_resources
    return @get_blocking_resources if defined?(@get_blocking_resources)
    @get_blocking_resources = blocking_resources(concurrency, repository&.owner)
  end

  def original_workflow_run_execution
    # Set original execution to current execution for back compat
    if original_workflow_run_execution_id.nil?
      # Connected to reading role by default, so explicitly connect to writing role to update original execution
      ActiveRecord::Base.connected_to(role: :writing) do
        update(original_workflow_run_execution_id: workflow_run_execution_id)
      end
    end

    # Call auto-generated method to actually retrieve execution
    super
  end

  def cloned_from_previous_run?
    original_workflow_run_execution_id.present? && original_workflow_run_execution_id != workflow_run_execution_id
  end

  def get_summary
    return nil if summary_url.blank?

    if ActionsResults::Utils.is_results_url?(summary_url)
      # results://
      get_summary_from_results(summary_url)
    else
      # http:// or https://, etc
      get_summary_from_actions_service(summary_url)
    end
  rescue *HTTP_ERRORS => e
    GitHub.dogstats.increment("actions.workflow_job_run.get_summary.error", tags: ["error:#{e.class.name&.underscore}", "is_results:#{ActionsResults::Utils.is_results_url?(summary_url)}"])
    Failbot.report(e)
    nil
  end

  def reusable_job?
    # for reusable jobs, parent_job_id is in `<caller_name>.<called_name> format`
    parent_job_id&.include?(".")
  end

  private

  def actions_service_client
    GitHub::FaradayClient::Internal.new do |conn|
      conn.adapter Faraday.default_adapter
    end
  end

  def matches_workflow_run_repository
    if workflow_run && repository_id && repository_id != workflow_run&.repository_id
      errors.add(:repository, "does not match the workflow run's repository")
    end
  end

  def matches_check_run_repository
    if check_run && repository_id && repository_id != check_run&.repository_id
      errors.add(:repository, "does not match the check run's repository")
    end
  end

  # Request summary from results:
  # 1. Decode results:// URI to obtain the workflow run ID and workflow job run ID
  # 2. Make Twirp request to results-core to get the summary
  # 3. If twirp request is successful, return the normalized Actions::JobSummary object
  # 4. If twirp request fails, fallback to actions service job summary request from query params
  def get_summary_from_results(url)
    return nil unless url

    # the summary URI sent from the Results service will
    # be of the form: results://actions-results/run/<workflow run ID>/job/<workflow job run ID>
    matches = ActionsResults::Utils.get_ids_from_results_url(url)
    return nil unless matches

    res = ActionsResults::Twirp.job_summary_client.get_job_summary(
      workflow_run_backend_id: T.must(matches[:workflow_run_backend_id]),
      workflow_job_run_backend_id: T.must(matches[:workflow_job_run_backend_id]),
    )

    if res.call_succeeded?
      json_response = res.value.to_json
      hash = JSON.parse(json_response)

      Actions::JobSummary.from_results_hash(hash)
    else
      GitHub.dogstats.increment("actions.workflow_job_run.get_summary.fallback_to_actions_service", tags: ["status_code:#{res.status}"])
      # fallback to the actions service
      fallback_to_actions_service(url)
    end
  end

  # If the results request fails, we will fallback to actions service url from summary URL query params
  def fallback_to_actions_service(url)
    actions_url = ActionsResults::Utils.actions_url(url)

    get_summary_from_actions_service(actions_url)
  end

  # Request summary from actions service:
  # 1. GRPC request to obtain signed URL from launch
  # 2. Make HTTP request (with signed URL) to actions service
  # 3. Normalize to Actions::JobSummary
  def get_summary_from_actions_service(url)
    return nil unless url

    is_lab = workflow_run&.check_suite&.lab_workflow?

    resp = Launch::Twirp.checks_client(lab: !!is_lab).get_summary_exchange_url(
      repository: T.cast(repository, Repository), # rubocop:todo GitHub/AvoidCast
      unauthenticated_url: url,
    )

    return nil unless resp.value&.authenticated_url

    hmac_url = resp.value&.authenticated_url

    # request to actions service to get the contents of the job summary
    res = actions_service_client.get(hmac_url)
    return nil unless res.success?

    hash = JSON.parse(res.body)
    Actions::JobSummary.from_hash(hash)
  end
end
