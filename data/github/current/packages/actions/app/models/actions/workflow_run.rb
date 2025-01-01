# typed: false
# frozen_string_literal: true

class Actions::WorkflowRun < ApplicationRecord::Domain::RepositoriesActionsChecks
  self.ignored_columns = %w(completed_log_url)

  class NotDeleteableError < StandardError; end

  include Ability::Subject
  include Actions::WorkflowRun::NewsiesAdapter
  include GitHub::Relay::GlobalIdentification
  include GitHub::WorkflowConcurrency
  include GitHub::Tracing
  include Instrumentation::Model
  include Spam::Spammable
  include Repositories::BelongsToRepository

  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::WorkflowRun

  extend GitHub::Encoding
  force_utf8_encoding :action, :execution_graph, :head_branch, :name, :workflow_file_path

  PLACEHOLDER_TITLE = "(Unknown event)"

  SUCCESS = "success"
  COMPLETED = "completed"
  IN_PROGRESS = "in_progress"
  QUEUED = "queued"
  CANCELLED = "cancelled"
  PENDING = "pending"

  SUPPORTED_REUSE_EVENT_TYPES = %w[
    push
    pull_request
    merge_group
  ].freeze

  belongs_to_repository_via_domain
  destroy_in_background_with :repository,
    cross_shard_query_exempted: true,
    deletion_stage: GitHub::BackgroundDeletes::DeletionStage::RepositorySoftDelete
  belongs_to :workflow
  belongs_to :check_suite, inverse_of: :workflow_run

  belongs_to :actor, class_name: "User"

  has_many :artifacts, inverse_of: :workflow_run

  has_many :workflow_job_runs, ->(workflow_run) { where(repository_id: workflow_run.repository_id) }
  destroy_dependents_in_background :workflow_job_runs, sharding_key: :repository_id, sharding_value_key: :repository_id
  has_one :latest_workflow_run_job,
    -> (workflow_run) { includes(:check_run).where(repository_id: workflow_run.repository_id).order(id: :desc) },
    class_name: "Actions::WorkflowJobRun"

  # Hide workflow_run_executions from workflow_runs that were created before we create a new execution per retry
  has_many :workflow_run_executions, -> (workflow_run) { where(repository_id: workflow_run.repository_id) }, inverse_of: :workflow_run
  destroy_dependents_in_background :workflow_run_executions, sharding_key: :repository_id, sharding_value_key: :repository_id
  belongs_to :latest_workflow_run_execution, -> (workflow_run) { where(repository_id: workflow_run.repository_id) }, class_name: "Actions::WorkflowRunExecution"

  batch_method(:trigger) do |workflow_runs|
    triggers_by_workflow_run = {}

    workflow_runs_by_trigger_type_and_repo = workflow_runs.group_by { |run| [run.trigger_type, run.repository_id] }

    workflow_runs_by_trigger_type_and_repo.each do |trigger_and_repo_id, workflow_runs|
      trigger_type, repository_id = trigger_and_repo_id
      next unless trigger_type && repository_id

      triggers_by_id = if trigger_type == Repositories::Push.polymorphic_name
        Repositories.domain.pushes.by_repository_id(push_ids: workflow_runs.pluck(:trigger_id), repository_id: repository_id).index_by(&:id)
      else
        Platform::Loaders::ActiveRecord.load_all(trigger_type.constantize, workflow_runs.pluck(:trigger_id), column: :id, shard_key: { repository_id: repository_id }).sync.compact.index_by(&:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      workflow_runs.each do |workflow_run|
        triggers_by_workflow_run[workflow_run] = triggers_by_id[workflow_run.trigger_id]
      end
    end

    triggers_by_workflow_run
  end

  def trigger=(trigger)
    self.trigger_type = trigger&.class&.polymorphic_name
    self.trigger_id = trigger&.id
  end

  setup_spammable(:actor)

  delegate :duration, :failed?, :head_repository, :status, :conclusion, :push, :github_app, :created_at, :updated_at, :started_at, :completed_at, :cancelled_at, :commit, :creator, :creator_id, :async_readable_by?, :readable_by?, :has_reruns, :external_id, :completed_log_url, to: :check_suite

  before_create :set_run_number
  after_create :create_workflow_run_execution

  validate :matches_check_suite_repository
  validate :matches_workflow_repository
  validate :trigger_id_and_type_presence

  before_destroy :emit_workflow_run_deleted

  after_commit :notify_socket_subscribers, on: :create
  after_commit :notify_pull_request_socket_subscribers, on: [:create, :destroy]
  after_commit :synchronize_search_index
  after_commit :delete_workflow_if_no_runs, on: :destroy

  trace_method :synchronize_search_index
  trace_method :notify_pull_request_socket_subscribers
  trace_method :notify_socket_subscribers

  attr_accessor :workflow_run_execution_data

  scope :most_recent, -> { order(id: :desc) }

  # execution_graph can be a large JSON blob and is only used in a few places so the default scope excludes it
  default_scope { select(column_names - ["execution_graph"]) }
  scope :with_execution_graph, -> { unscoped }

  def self.emit_workflow_run_deleted(
    repository_id:,
    workflow_run_id:,
    check_suite_id:,
    execution_external_id:
  )
    GitHub.hydro_publisher.publish(
      {
        repository_id: repository_id,
        workflow_run_id: workflow_run_id,
        check_suite_id: check_suite_id,
        workflow_run_backend_id: execution_external_id
      },
      schema: "github.actions.v0.WorkflowRunDeleted",
    )
  end

  def billing_usage_line_items
    return @billing_usage_line_items if defined?(@billing_usage_line_items)

    check_run_ids = check_suite.check_runs.pluck(:id)

    line_item_response = billing_api_client.get_usage_line_items(
      product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:actions],
      custom_fields: {
        "actions.check_run.id" => {
          "field_values" => check_run_ids.map(&:to_s)
        }
      }
    )

    if line_item_response.is_a?(Billing::Api::ClientWrapper::BillingClientError)
      []
    else
      @billing_usage_line_items = line_item_response.map do |usage_line_item|
        Billing::Actions::UsageLineItemWrapper.new(usage_line_item)
      end
    end
  end

  def has_billing_data?
    return false if GitHub.enterprise?
    check_suite.completed? && billing_usage_line_items.any?
  end

  # It's possible for a run to not have billing data. And it's unlikely it ever will.
  # - It could be old, before we started recording data (April 5th, 2020)
  # - There could have been an incident effecting hydro or processing
  #
  # For these we show a message to the user that it's unavailable.
  def billing_data_unavailable?
    if check_suite.completed? && check_suite.completed_at
      return check_suite.completed_at < 20.minutes.ago
    end

    false
  end

  # Total duration of seconds as seen by billing for this workflow.
  # This includes all re-runs. Does NOT include the OS multiplier.
  #
  # May be slightly delayed after workflow is complete. Data from a background job.
  def billing_duration_in_seconds
    @billing_duration_in_seconds ||= billing_usage_line_items.sum do |line_item|
      line_item.duration_in_minutes.minutes.in_seconds
    end
  end

  def action_check_runs
    check_suite.check_runs.select { |check_run| check_run.is_actions_check_run? }
  end

  def jobs
    check_suite.check_runs
  end

  def latest_jobs
    check_suite.latest_check_runs
  end

  def get_blocking_resources
    get_blocking_resources = []
    # Get for checksuite
    check_suite_blocker = blocking_resources(concurrency, repository.owner)
    check_suite_blocker.each { |blocker| blocker[:blocked_at_level] = "workflow" } if check_suite_blocker.present?
    get_blocking_resources.append(check_suite_blocker) if check_suite_blocker.present?

    # Get for check_runs
    pending_jobs_concurrencies = latest_check_runs
      .filter_map { |job| job.workflow_job_run&.concurrency if job.pending? }

    pending_jobs_concurrencies.uniq.each do |concurrency|
      check_run_blocker = blocking_resources(concurrency, repository.owner)
      check_run_blocker.each { |blocker| blocker[:blocked_at_level] = "job" } if check_run_blocker.present?
      get_blocking_resources.append(check_run_blocker) if check_run_blocker.present?
    end

    get_blocking_resources.flatten
  end

  def latest_workflow_job_runs(execution: nil)
    execution ||= latest_workflow_run_execution
    if execution.nil?
      return latest_workflow_job_runs_without_execution
    end

    execution.workflow_job_runs.includes(:check_run)
  end

  def latest_workflow_job_runs_with_deployments(execution: nil)
    execution ||= latest_workflow_run_execution
    if execution.nil?
      return latest_workflow_job_runs_without_execution_with_deployments
    end

    execution.workflow_job_runs.includes(check_run: { deployment: :statuses })
  end

  def latest_check_runs(execution: nil)
    ActiveRecord::Base.connected_to(role: :reading) do
      execution ||= latest_workflow_run_execution
      if execution.nil?
        check_runs = check_suite.latest_check_runs
      else
        check_run_ids = execution.workflow_job_runs.pluck(:check_run_id)
        check_runs = check_run_ids.empty? ? CheckRun.none : CheckRun.where(id: check_run_ids)
      end

      check_runs.load
    end
  end

  def is_clone?
    self.cloned_workflow_run_id.present? && self.cloned_workflow_run_id != self.id
  end

  def is_parent_of_clone?
    self.cloned_workflow_run_id.present? && self.cloned_workflow_run_id == self.id
  end

  def expired_logs?
    check_suite.check_runs.where(repository_id: repository_id).any? { |check_run| check_run.expired_logs? }
  end

  def title
    async_title.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  def async_title
    return Promise.resolve(name) if event == "dynamic" && name.present?
    return Promise.resolve(name) if explicit_name? && name.present?

    async_batch_trigger.then do |trigger|
      case trigger
      when Issue, PullRequest
        trigger.title
      when IssueComment
        trigger.async_issue.then do |issue|
          issue.title
        end
      when Repositories::Push
        async_repository.then do |repository|
          Platform::Loaders::GitObject.load(repository, trigger.after).then do |commit|
            if commit && commit.message.present?
              commit.short_message_text
            else
              async_fallback_title
            end
          end
        end
      when Release
        trigger.name.present? ? trigger.name : trigger.tag_name
      when Deployment
        trigger.environment if trigger.environment.present?
      else
        async_fallback_title
      end
    end
  end

  def permalink(include_host: true, pull_request_number: nil)
    if pull_request_number
      "#{check_suite.repository.permalink(include_host: include_host)}/actions/runs/#{id}?pr=#{pull_request_number}"
    else
      "#{check_suite.repository.permalink(include_host: include_host)}/actions/runs/#{id}"
    end
  end

  # Unique identifier for this issue used in email messages.
  def message_id
    "<#{repository.name_with_display_owner}/workflow-run/#{global_relay_id}/#{updated_at.to_i}@#{GitHub.urls.host_name}>"
  end

  def workflow_file_link
    repo_url = check_suite.repository.permalink(include_host: true)
    "#{repo_url}/blob/#{commit_oid}/#{workflow_file_path}"
  end

  def dynamic_workflow?
    workflow_file_path&.start_with?(Actions::Workflow::DYNAMIC_BASE_PATH)
  end

  def codespaces_prebuild_dynamic_workflow_run?
    prebuild_workflow_base = "#{Actions::Workflow::DYNAMIC_BASE_PATH}#{Apps::Privileged::Codespaces::PREBUILD_DYNAMIC_WORKFLOW_INTEGRATION_NAME}"
    workflow_file_path&.start_with?(prebuild_workflow_base)
  end

  def required_workflow_run?
    imposer_repository_id > 0
  end

  def commit_oid
    commit&.oid
  end

  # Post-actor backfill: Remove this method, rely on the `actor` method mixed in by the `belongs_to` association.
  def actor
    # fallback to the check suite until we run a transition to backfill actor_id
    super || check_suite.creator || check_suite.pusher
  end

  ############################################################################
  ## Search

  # Public: Synchronize this workflow run with its representation in the search
  # index. If the workflow run is newly created or modified in some fashion, then
  # it will be updated in the search index. If the workflow run has been
  # destroyed, then it will be removed from the search index. This method
  # handles both cases.
  #
  def synchronize_search_index
    if self.destroyed? || check_suite.nil?
      reason = self.destroyed? ? "destroyed" : "check_suite_nil"
      RemoveFromSearchIndexJob.perform_later("workflow_run", self.id, self.repository_id)
      GitHub.logger.info("Removing workflow run from search index", {
        "code.namespace" => self.class.name,
        "code.function" => "synchronize_search_index",
        "gh.catalog_service" => "github/actions",
        "gh.actions.workflow_run.id" => id,
        "gh.actions.synchronize_search_reason" => reason,
      })
      GitHub.dogstats.increment("workflow_runs.remove_from_search_index", tags: ["reason:#{reason}"])
    elsif self.workflow_file_path.present?
      Search.add_to_search_index("workflow_run", self.id)
    end
    self
  end

  def self.search(query:, repo: nil, workflow: nil, workflow_id: nil, current_user: nil, remote_ip: nil,
                  user_session: nil, page: 1, per_page: 25, hide_spammy_runs: false,
                  show_spammy_runs_by_current_user: true, head_repo_id: nil, unsupported_conclusions: nil, is_lab: false,
                  sort: nil, **kargs)
    is_lab ||= workflow&.end_with?("(Lab)")
    workflow = workflow&.sub(" (Lab)", "") if is_lab
    query = "workflow:\"#{workflow}\" #{query}" if workflow

    unless query.is_a?(String)
      raise ArgumentError, "query must be a String: #{query.class}"
    end

    hash = {
      phrase: query,
      query: Search::Queries::WorkflowRunQuery.parse(query),
      repo_id: repo&.id,
      head_repo_id: head_repo_id,
      unsupported_conclusions: unsupported_conclusions,
      aggregations: :state,
      page: page,
      per_page: per_page,
      current_user: current_user,
      remote_ip: remote_ip,
      user_session: user_session,
      source_fields: false,
      lab: is_lab,
      workflow_id: workflow_id,
      hide_spammy_runs: hide_spammy_runs,
      show_spammy_runs_by_current_user: show_spammy_runs_by_current_user,
      sort: sort
    }

    es = ::Search::Queries::WorkflowRunQuery.new(hash).execute

    workflow_runs = WillPaginate::Collection.create(page, per_page, es.total) do |pager|
      pager.replace es.results.map { |result| result["_model"] }
    end

    {
      workflow_runs: workflow_runs,
      total_count: es.total
    }
  rescue Search::Query::MaxOffsetError
    {
      workflow_runs: [],
      total_count: 0
    }
  end

  def self.distinct_by(repo:, field:, size: 10, current_user: nil, remote_ip: nil, user_session: nil, filter_empty_value: true)
    hash = {
      phrase: nil,
      query: nil,
      repo_id: repo&.id,
      aggregations: field,
      aggregations_size: size,
      page: 1,
      per_page: 0, #not interested in result set
      current_user: current_user,
      remote_ip: remote_ip,
      user_session: user_session,
      source_fields: false,
    }

    es = ::Search::Queries::WorkflowRunQuery.new(hash).execute
    values = es.aggregations[field.to_s]["buckets"].map { |entry| entry["key"] }

    values.delete("") if filter_empty_value

    {
      distinct_values: values,
    }
  rescue Search::Query::MaxOffsetError
    {
      distinct_values: [],
    }
  end

  def workflow_name
    name = workflow.name
    name.present? ? name : Actions::Workflow::PLACEHOLDER_NAME
  end

  def short_head_sha
    head_sha.first(Commit::ABBREVIATED_OID_LENGTH)
  end

  def deleteable?
    return true if check_suite.nil? || check_suite.completed?

    check_suite.created_at < Time.zone.now - CheckSuite::DEFAULT_STALE_THRESHOLD
  end

  def hard_delete(actor:)
    raise NotDeleteableError unless deleteable?

    if check_suite.present? && !check_suite.completed?
      result = check_suite.cancel(actor: actor, force: true)
    end

    transaction do
      check_suite.destroy! if check_suite.present?
      destroy!
    end

    GitHub.instrument "workflows.delete_workflow_run", event_payload.merge(actor: actor)
    GitHub.dogstats.increment("workflow_run.hard_delete")
  end

  def workflow_runs_channel
    GitHub::WebSocket::Channels.workflow_runs(repository)
  end

  # Params:
  # - execution - the workflow run execution, will be used to filter workflow_job_runs
  # - blankstate - no workflow_job_runs will be pulled in if blankstate is true. Used for retry_blankstate
  # - include_deployments - pull in associated deployments and gates associated with the latest check_run ids.
  #                         Used for graph UI in workflow run summary.
  def graph(execution: nil, blankstate: false, include_deployments: false)
    return nil unless has_attribute?(:execution_graph) || execution&.has_attribute?(:execution_graph)
    if execution&.execution_graph.present?
      graph_json = execution.execution_graph
    elsif execution_graph.present?
      graph_json = execution_graph
    else
      return nil
    end
    jobs =
      if blankstate
        Actions::WorkflowJobRun.none
      elsif include_deployments
        latest_workflow_job_runs_with_deployments(execution: execution)
      else
        latest_workflow_job_runs(execution: execution)
      end

    graph = Actions::Graph.new(
      name: File.basename(workflow_file_path),
      trigger: event,
      json: graph_json,
      workflow_job_runs: jobs.to_a, # materialize the jobs
    )

    # we will only draw the graph if it's valid after being parsed
    graph.is_valid? ? graph : nil
  end

  def approval_logs_channel
    GitHub::WebSocket::Channels.actions_approval_logs(self)
  end

  def artifacts_channel
    GitHub::WebSocket::Channels.actions_artifacts(self)
  end

  def gate_requests_channel
    GitHub::WebSocket::Channels.actions_gate_requests(self)
  end

  # fires on re-run when a new execution is created
  def execution_channel
    GitHub::WebSocket::Channels.actions_execution_channel(self)
  end

  def emit_creation_audit_log(actor:)
    return unless can_emit_audit_logs?
    GitHub.instrument "workflows.created_workflow_run", event_payload.merge(actor: actor)
  end

  def emit_completion_audit_log(actor:, attempt:)
    return unless can_emit_audit_logs?
    GitHub.instrument "workflows.completed_workflow_run", event_payload.merge(
      actor: actor,
      completed_at: completed_at,
      conclusion: conclusion,
      re_run: has_reruns,
      run_attempt: attempt,
    )
  end

  def emit_rerun_audit_log(actor:, attempt: nil)
    return unless can_emit_audit_logs?
    GitHub.instrument "workflows.rerun_workflow_run", event_payload.merge(
      actor: actor,
      run_attempt: attempt,
      rerun_type: "all_jobs",
    )
  end

  def emit_rerun_only_failed_audit_log(actor:, attempt: nil)
    return unless can_emit_audit_logs?
    GitHub.instrument "workflows.rerun_workflow_run", event_payload.merge(
      actor: actor,
      run_attempt: attempt,
      rerun_type: "failed_jobs",
    )
  end

  def emit_rerun_single_job_audit_log(actor:, attempt: nil, check_run_id: nil)
    return unless can_emit_audit_logs?
    GitHub.instrument "workflows.rerun_workflow_run", event_payload.merge(
      actor: actor,
      run_attempt: attempt,
      rerun_type: "single_job",
      check_run_id: check_run_id,
    )
  end

  def emit_cancel_audit_log(actor:)
    return unless can_emit_audit_logs?
    GitHub.instrument "workflows.cancel_workflow_run", event_payload.merge(
      actor: actor,
      cancelled_at: cancelled_at
    )
  end

  def instrument_workflow_run_completed(actor:, check_suite_id:)
    GlobalInstrumenter.instrument "workflow_run_execution.completed", event_payload.merge(
      actor_id: actor.id,
      attempt: latest_workflow_run_execution.attempt,
      conclusion: conclusion,
      check_suite_id: check_suite_id,
      repository_id: repository.id,
      repository_owner_id: repository.owner.id,
      status: status,
      workflow_run_external_id: latest_workflow_run_execution.external_id,
      workflow_run_path: workflow_file_path,
      completed_at: completed_at,
    )
  end

  def event_payload
    {
      started_at: check_suite.nil? ? nil : started_at,
      event: event,
      name: name,
      workflow_run_id: id,
      workflow: workflow,
      workflow_file_path: workflow_file_path,
      head_branch: head_branch,
      head_sha: head_sha,
      repo: repository,
      org: repository.organization,
      trigger_id: trigger_id,
      workflow_run_action: action,
      run_number: run_number
    }
  end

  def notify_pull_request_socket_subscribers(rerun: false)
    return unless check_suite
    return unless rerun || check_suite.action_required?

    data = {
      timestamp: updated_at,
      reason: "action_required workflow_run ##{id}: #{status}",
    }

    check_suite.matching_pull_requests.each do |pull_request|
      GitHub::WebSocket.notify_repository_channel(
        repository,
        pull_request_channel(pull_request),
        data,
      )
    end
  end

  def latest_workflow_run_execution
    # Set latest if not already set
    if latest_workflow_run_execution_id.nil?
      # Connected to reading role by default, so explicitly connect to writing role to update latest
      ActiveRecord::Base.connected_to(role: :writing) do
        update(latest_workflow_run_execution: workflow_run_executions.reorder(attempt: :desc).first)
      end
    end

    # Call auto-generated method to actually retrieve execution
    super
  end

  def latest_workflow_run_execution_with_graph
    Actions::WorkflowRunExecution.unscoped { latest_workflow_run_execution }
  end

  def has_multiple_attempts
    latest_workflow_run_execution.present? && latest_workflow_run_execution.attempt > 1
  end

  def previous_attempt_num
    has_multiple_attempts && latest_workflow_run_execution.attempt - 1
  end

  def current_attempt_num
    has_multiple_attempts && latest_workflow_run_execution.attempt
  end

  # Processing retry if checksuite has been reset but the new execution has not yet been created
  def processing_retry?
    return false unless latest_workflow_run_execution.present?
    # If checksuite is pending/queued but the current execution is completed, then a new execution has not yet been created
    status.in?([PENDING, QUEUED]) && latest_workflow_run_execution.completed?
  end

  def create_new_workflow_execution(external_id:, attempt:, actor: nil, execution_graph: nil, referenced_workflows: nil)
    # Copy execution graph from previous attempt if no graph is provided
    # Execution graph is only sent/stored for executions using reusable workflows, but is not sent for partial reruns
    if execution_graph.blank?
      previous_execution_graph = latest_workflow_run_execution_with_graph&.execution_graph
      if previous_execution_graph.present?
        execution_graph = previous_execution_graph
      end
    end

    execution = nil
    transaction do
      # This won't entirely solve for a race condition here, but we don't currently have a unique index we can
      # use in an "ON DUPLICATE KEY UPDATE" or similar, so best we can do is load then create/update
      existing_execution = workflow_run_executions.find_by(attempt: attempt, external_id: external_id)
      if existing_execution
        execution = existing_execution
      else
        execution = workflow_run_executions.build(attempt: attempt, external_id: external_id)
      end

      execution.update!(
        workflow_run: self,
        actor: actor || self.actor,
        repository: repository,
        started_at: started_at,
        execution_graph: execution_graph,
        referenced_workflows: referenced_workflows
      )

      update!(latest_workflow_run_execution: execution)

      check_suite.update!(external_id: external_id)
    end

    data = {
      timestamp: updated_at,
      wait: default_live_updates_wait,
      reason: "Execution created",
    }

    GitHub::WebSocket.notify_repository_channel(repository, execution_channel, data)
    execution
  end

  # Deletes logs from check suite and workflow_run_executions
  # Used to delete logs from API and UI
  def delete_logs(actor:)
    # Prevent deleting logs while run in progress to prevent strange behavior during partial reruns
    raise NotDeleteableError unless check_suite.completed?

    check_suite_log_url = check_suite.completed_log_url
    check_suite.delete_logs(actor: actor)

    workflow_run_executions.each do |workflow_run_execution|
      workflow_run_execution.delete_logs(check_suite_log_url: check_suite_log_url)
    end

    if FeatureFlag.vexi.enabled_or_raise?(:actions_results_delete_logs, repository) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      workflow_run_executions.each do |workflow_run_execution|
        result = ActionsResults::Twirp.log_client.delete_logs(
          workflow_run_backend_id: workflow_run_execution.external_id
        )
        unless result.call_succeeded?
          GitHub.dogstats.increment("actions.workflow_run.delete_logs", tags: ["status_code:#{result.status}"])
        end
      end
    end
  end

  def success?
    self.conclusion == SUCCESS
  end

  def completed?
    self.status == COMPLETED
  end

  def in_progress?
    self.status == IN_PROGRESS
  end

  def pending?
    self.status == PENDING
  end

  def queued?
    self.status == QUEUED
  end

  def succeeded?
    check_suite.completed? && check_suite.success?
  end

  def cancelled?
    self.conclusion == CANCELLED && cancelled_at.present?
  end

  # Only includes job runs that are failed/incomplete and also rerequestable
  def failed_workflow_job_runs
    latest_workflow_job_runs.select do |job_run|
      check_run = job_run.check_run
      check_run.failed? && check_run.actions_rerequestable?
    end
  end

  # Has any job runs that are failed/incomplete and also rerequestable
  def has_failed_workflow_job_runs?
    latest_check_runs.any? do |check_run|
      check_run.failed? && check_run.actions_rerequestable?
    end
  end

  # Uses graph to return list of jobs downstream of passed in jobs
  def downstream_jobs_for(jobs: [])
    parent_job_ids = jobs.map(&:parent_job_id)
    downstream_jobs = []
    groups_to_add_and_evaluate = []

    if parent_job_ids.any?
      # Stages contain groups which are not dependent on each other. The first stage is groups with no inputs.
      # Stages are ordered based on group inputs/outputs such that downstream jobs are always in a later stage than their dependenceis
      graph&.stages&.each do |stage|
        stage.groups.each do |group|
          if groups_to_add_and_evaluate.include?(group.dom_id)
            groups_to_add_and_evaluate.delete(group.dom_id)
            downstream_jobs += group.workflow_job_runs
            groups_to_add_and_evaluate += group.outputs # outputs are dom_ids of downstream groups
          elsif group.jobs.any? { |job| parent_job_ids.any?(job.id) } # if any of the passed in jobs are in this group
            groups_to_add_and_evaluate += group.outputs
          end
        end
      end
    end

    downstream_jobs
  end

  # Internal: an abstract collection, for the sub-resources of a WorkflowRun available for permissions.
  def resources
    Actions::WorkflowRun::Resources.new(self)
  end

  def logs_via_results_service?
    (FeatureFlag.vexi.enabled_or_raise?(:actions_favor_results_service_logs, repository) && !opt_out_from_results?) || is_actions_four_nines_run? # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  def opt_out_from_results?
    FeatureFlag.vexi.enabled_or_raise?(:actions_opt_out_results_service, repository) || FeatureFlag.vexi.enabled_or_raise?(:actions_opt_out_results_service, repository.owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  # helper method to determine if a this execution is created by Actions Four Nines Services.  Only 4-9s runs are created by
  # Run Service and have `run_stamp_url` field set.
  def is_actions_four_nines_run?
    workflow_run_executions.first&.run_stamp_url.present?
  end

  # Returns if the branch or tag name is relevant to show in the UI for this workflow run
  def ref_name_relevant?
    %w[push pull_request workflow_dispatch schedule dynamic].include? event
  end

  # Fall back to the check suite's head branch ref if we need a fully qualified reference
  # There is a bug where workflow runs are not created with fully qualified refs, so we cannot fall back in all cases
  # See: https://github.com/github/github/blob/47098f4333c2f2bd1663d6c8844f66c1db7fbda6/packages/checks/app/models/check_suite.rb#L912
  def head_branch(fully_qualified: false)
    return check_suite.head_branch(fully_qualified:) if fully_qualified
    super()
  end

  def can_user_view_workflow_file?(current_user)
    workflow_valid = workflow_file_path.present? && !dynamic_workflow?
    return workflow_valid unless required_workflow_run?

    # if the workflow is required, check that the user has pull access to source repo
    source_repo = Repositories::Public.find_active(imposer_repository_id)
    return false if source_repo.nil?

    workflow_valid && source_repo.pullable_by?(current_user)
  end

  private

  def matches_check_suite_repository
    if check_suite && repository_id && repository_id != check_suite.repository_id
      errors.add(:repository, "does not match the check suite's repository")
    end
  end

  def matches_workflow_repository
    if workflow && repository_id && repository_id != workflow.repository_id
      errors.add(:repository, "does not match the workflow's repository")
    end
  end

  def trigger_id_and_type_presence
    if trigger_type.present? != trigger_id.present?
      errors.add(:trigger, "must have both a trigger_id and trigger_type or neither")
    end
  end

  # Internal: Do the actual WebSocket notification
  def notify_socket_subscribers
    data =
      {
        timestamp: created_at,
        reason: "workflow_run ##{id} created: #{status}",
        wait: default_live_updates_wait + 3000,
      }

    GitHub::WebSocket.notify_repository_channel(repository, workflow_runs_channel, data)
  end

  def pull_request_channel(pull_request)
    GitHub::WebSocket::Channels.pull_request_workflow_run_state(pull_request)
  end

  def set_run_number
    ActiveRecord::Base.connected_to(role: :writing) do
      # Ensure we are connected to the writing role here because we need write access on mysql1
      self.run_number = Sequence.next(workflow)
    end
  end

  def can_use_enterprise_features?
    return true if GitHub.enterprise?
    return false if repository.organization.nil?
    repository.organization.plan.business_plus? || repository.organization.plan.enterprise?
  end

  def can_emit_audit_logs?
    can_use_enterprise_features?
  end

  def create_workflow_run_execution
    external_id_to_use = external_id
    if external_id.present? && check_suite.original_actions_external_id != external_id
      # the execution is cloned
      external_id_to_use = check_suite.original_actions_external_id
    end

    execution = workflow_run_executions.create(
      workflow_run: self,
      completed_log_url: completed_log_url,
      external_id: external_id_to_use,
      actor: actor,
      repository: repository,
      started_at: started_at,
      conclusion: conclusion,
      status: status,
      completed_at: completed_at,
      attempt: 1,
      referenced_workflows: workflow_run_execution_data&.referenced_workflows,
    )

    update!(latest_workflow_run_execution: execution)
  end

  def billing_api_client
    return @billing_api_client if defined?(@billing_api_client)

    owner = repository.owner
    @billing_api_client = ::Billing::Api::ClientWrapper.new(
      billable_owner: owner.billable_owner,
      owner: owner.is_organization_billed_through_business? ? owner : nil,
    )
  end

  # Older workflow runs won't have any workflow run executions, so we need to rely on
  # using the check suite timestamps to retrieve workflow jobs
  def latest_workflow_job_runs_without_execution
    latest_check_run_ids = Checks.domain.check_runs.latest_ids_for_check_suite(check_suite)

    jobs = Actions::WorkflowJobRun
             .includes(:check_run)
             .where(repository_id: repository_id, check_run: latest_check_run_ids)
  end

  def latest_workflow_job_runs_without_execution_with_deployments
    latest_check_run_ids = Checks.domain.check_runs.latest_ids_for_check_suite(check_suite)

    # Query the deployments manually first to be able to force an index on them
    deployments = Deployment.by_check_runs(latest_check_run_ids)
                            .includes(:statuses)
                            .index_by(&:check_run_id)

    jobs = Actions::WorkflowJobRun
             .includes(:check_run)
             .where(repository_id: repository_id, check_run: latest_check_run_ids)

    jobs.each { |job| job.check_run.association(:deployment).target = deployments[job.check_run_id] }

    jobs
  end

  def async_fallback_title
    async_check_suite.then do |check_suite|
      next PLACEHOLDER_TITLE if check_suite.nil?
      next check_suite.action if check_suite.event == "repository_dispatch" && check_suite.action.present?

      async_workflow.then do |workflow|
        workflow.name.presence || PLACEHOLDER_TITLE
      end
    end
  end

  def delete_workflow_if_no_runs
    workflow&.delete_if_no_runs
  end

  def emit_workflow_run_deleted
    workflow_run_executions.pluck(:external_id).each do |external_id|
      Actions::WorkflowRun.emit_workflow_run_deleted(
        repository_id: self.repository_id,
        workflow_run_id: self.id,
        check_suite_id: self.check_suite_id,
        execution_external_id: external_id
      )
    end
  end
end
