# typed: strict
# frozen_string_literal: true

class Issues::AgentAssignmentsController < IssuesController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include PullRequests::DatabaseSelection

  # Based on the maximum number of issues on an issues#index page
  MAX_PAGE_SIZE = 100

  before_action :login_required
  before_action :require_copilot_swe_agent_enabled, except: [:destroy]
  before_action :try_parse_json_params, only: [:create]
  before_action :validate_assignment_params, only: [:create]

  allow_verified_fetch only: [:create, :destroy]

  prepend_around_action :route_reads_to_replicas, only: [:create, :destroy]

  # Custom exception classes for better error handling
  class RepositoryNotFoundError < StandardError; end
  class BotAccessError < StandardError; end
  class BotNotAssignableError < StandardError; end
  class CopilotSweAgentDisabledError < StandardError; end

  sig { void }
  def destroy
    actor = T.must(current_user)
    type_filter = { subject_type: :issue }

    assignment = AgentAssignment.find_by({
      id: params[:id],
      repository_id: current_repository.id,
    }.merge(type_filter))

    unless assignment
      render json: { error: "Agent assignment not found" }, status: :not_found
      return
    end

    issue = assignment.subject
    unless issue
      render json: { error: "Issue not found" }, status: :not_found
      return
    end

    unless issue.assignable_by?(actor: actor)
      render json: { error: "You do not have permission to modify this issue" }, status: :forbidden
      return
    end

    begin
      assignment.destroy!
    rescue ActiveRecord::RecordNotDestroyed
      render json: { error: assignment.errors.full_messages.to_sentence.presence || "Failed to remove agent assignment" }, status: :unprocessable_entity
      return
    rescue ActiveRecord::ActiveRecordError => error
      Failbot.report(error, {
        app: "github",
        feature: "issues_copilot_assign",
        context: "agent_assignments_controller#destroy"
      })
      render json: { error: "Something went wrong while removing the agent assignment. Please try again later." }, status: :internal_server_error
      return
    end

    # Notify subscribers so the UI updates in real time
    data = {
      timestamp: Time.now.to_i,
      wait: issue.default_live_updates_wait,
      reason: "agent assignment removed for issue ##{issue.id}",
    }
    channel = GitHub::WebSocket::Channels.issue(issue)
    GitHub::WebSocket.notify_issue_channel(issue, channel, data)
    Platform::Schema.subscriptions.trigger(:issue_updated, { id: issue.global_relay_id }, object: { issue_metadata_updated: true })

    render json: { ok: true }, status: :ok
  end

  sig { void }
  def create
    issue_ids = params[:issue_ids].map(&:to_i)
    issues = load_issues_for_numbers(issue_ids)
    not_found = issue_ids - issues.map(&:number)
    unless not_found.empty?
      render json: { error: "Issue(s) not found: #{not_found.join(', ')}" }, status: :not_found
      return
    end

    actor = T.must(current_user)
    return unless issues_assignable_by?(actor, issues)

    assignment_attributes = build_assignment_attributes
    return unless assignment_attributes

    # Verify agent is enabled for the repository
    agent_id = assignment_attributes.agent_id
    if agent_id.nil? || agent_id.zero?
      # Use default Copilot Coding Agent if none specified
      agent = AgenticApp::CopilotAgent.instance
    else
      agent = AgenticApp.agent_for_integration_id(agent_id)
    end

    unless agent
      render json: { error: "The agent was not found in this repository." }, status: :not_found
      return
    end

    unless agent.enabled_for_repository?(current_repository, actor)
      render json: { error: "Agent is not enabled for this repository" }, status: :forbidden
      return
    end

    if current_repository != assignment_attributes.target_repository
      unless agent.enabled_for_repository?(assignment_attributes.target_repository, actor)
        render json: { error: "Agent is not enabled for the target repository" }, status: :forbidden
        return
      end
    end

    app = agent.integration
    unless app
      render json: { error: "The agent was not found in this repository." }, status: :not_found
      return
    end

    token = CopilotSessions::CopilotApiToken.get_encrypted(
      user: actor,
      entry_point: :agent_assignments_controller_create,
      user_session: user_session
    )
    assignment_results = Issues.domain.copilot.assign_copilot_to_issues(
      actor: actor,
      issues: issues,
      assignment_attributes: assignment_attributes,
      token: token,
      use_async: true,
      user_session_id: user_session&.id
    )

    jobs = assignment_results[:jobs]

    if assignment_results[:exceptions]&.any?
      handle_errors(assignment_results[:exceptions].first, assignment_attributes: assignment_attributes, jobs: jobs)
      return
    end

    bot = agent.integration&.bot
    unless bot
      render json: { error: "Agent not found" }, status: :not_found
      return
    end

    agent_info = {
      id: bot.global_relay_id,
      login: agent.slug,
      name: bot.name,
      avatarUrl: bot.primary_avatar_url(64),
      isAgent: true,
      displayName: agent.display_name,
      profileResourcePath: app&.public_app_path,
    }

    render json: {
      jobs: jobs,
      # TODO: remove once we confirm clients have migrated to the new 'agent' field
      copilot: agent_info,
      agent: agent_info,
    }, status: :ok
  end

  private

  sig { params(block: T.proc.void).void }
  def route_reads_to_replicas(&block)
    if FeatureFlag.vexi.enabled?(:web_read_from_replicas_controller, ControllerActor.new(self.class), default: false)
      use_replica_clusters([
        ApplicationRecord::Mysql1,
        ApplicationRecord::Repositories,
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::Iam,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Copilot,
        ApplicationRecord::Ballast,
      ], &block)
    else
      block.call
    end
  end

  sig { void }
  def validate_issue_ids
    issue_ids = params["issue_ids"]

    unless issue_ids.is_a?(Array)
      raise ArgumentError, "issue_ids must be an array"
    end

    if issue_ids.empty?
      raise ArgumentError, "issue_ids cannot be empty"
    end

    unless issue_ids.all? { |id| id.to_s.match?(/\A\d+\z/) }
      raise ArgumentError, "All issue_ids must be numeric"
    end

    unless issue_ids.size <= MAX_PAGE_SIZE
      raise ArgumentError, "can't assign the agent to more than #{MAX_PAGE_SIZE} issues at a time"
    end
  end

  sig { void }
  def require_copilot_swe_agent_enabled
    render_404 unless copilot_swe_agent_enabled?
  end

  sig { returns(T::Boolean) }
  def copilot_swe_agent_enabled?
    current_repository.copilot_swe_agent_enabled?(current_user) || false
  end

  sig { params(app: T.nilable(Integration), target_repository: T.nilable(Repositories::IRepository)).returns(T.nilable(Integration)) }
  def ensure_copilot_swe_agent_is_enabled!(app, target_repository)
    raise RepositoryNotFoundError unless target_repository

    installation = IntegrationInstallation.with_repository(target_repository).find_by(integration: app&.id)
    unless Apps::Privileged.capable?(:installed_globally, app: app)
      raise BotAccessError if installation.nil?
    end

    unless Apps::Privileged.capable?(:is_assignable, app: app)
      raise BotNotAssignableError
    end

    # Convert to Repository model to access methods not on the interface
    target_repository_obj = T.cast(target_repository, Repository) # rubocop:todo GitHub/AvoidCast
    unless target_repository_obj.copilot_swe_agent_enabled?(current_user)
      raise CopilotSweAgentDisabledError
    end

    app
  end

  sig { void }
  def validate_assignment_params
    errors = []

    if action_name == "create"
      begin
        validate_issue_ids
      rescue ArgumentError
        errors << "issue_ids must be a non-empty array of up to #{MAX_PAGE_SIZE} numeric values"
      end
    end

    # Return validation errors if any
    unless errors.empty?
      render json: {
        error: errors.join(", ")
      }, status: :unprocessable_entity
    end
  end

  sig { returns(T.nilable(Issues::AgentAssignmentNewAttributes)) }
  def build_assignment_attributes
    target_repository = if params[:repo_name_with_owner].present?
      Repositories.domain.by_qualified_name(params[:repo_name_with_owner])
    else
      current_repository
    end
    if target_repository.nil?
      render json: { error: "Repository not found." }, status: :not_found
      return
    end

    # NOTE: Must downcast because IRepository doesn't have visible_and_readable_by? method
    target_repo = T.cast(target_repository, Repository) # rubocop:disable GitHub/AvoidCast
    unless target_repo.writable_by?(current_user)
      render json: { error: "Repository not found." }, status: :not_found
      return
    end

    if target_repo.archived?
      render json: { error: "Cannot assign the agent to issues in archived repositories." }, status: :unprocessable_entity
      return
    end

    # Only allow model parameter if feature flag is enabled
    model = if FeatureFlag.vexi.enabled?(:coding_agent_model_selection, current_user, default: false)
      params[:model]
    end

    agent_id = params[:agent_id].present? ? params[:agent_id].to_i : nil

    assignment_attributes = Issues::AgentAssignmentNewAttributes.new(
      target_repository: target_repository,
      base_ref: params[:base_ref],
      custom_instructions: params[:custom_instructions],
      custom_agent: params[:custom_agent],
      agent_id: agent_id,
      remote_ip: request&.remote_ip,
      model: model,
      skip_pull_request: ActiveModel::Type::Boolean.new.cast(params[:skip_pull_request]),
    )
  end

  sig { params(numbers: T::Array[Integer]).returns(T::Array[Issue]) }
  def load_issues_for_numbers(numbers)
    return [] if numbers.empty?
    # Use reading role and scoped to current repository for safety
    ActiveRecord::Base.connected_to(role: :reading) do
      current_repository.issues.where(number: numbers).to_a
    end
  end

  sig { params(actor: User, issues: T::Array[Issue]).returns(T::Boolean) }
  def issues_assignable_by?(actor, issues)
    auth_promises = issues.map { |issue| issue.async_assignable_by?(actor: actor) }
    auth_results = Promise.all(auth_promises).sync
    unauthorized_issues = issues.zip(auth_results).reject { |_, can_assign| can_assign }.map { |issue, _| issue.number }

    unless unauthorized_issues.empty?
      render json: { error: "Forbidden to assign to issue(s): #{unauthorized_issues.join(', ')}" }, status: :forbidden
      return false
    end

    true
  end

  # Handles errors raised by queue_agent_orchestration and renders appropriate JSON error responses.
  sig { params(error: Exception, assignment_attributes: Issues::AgentAssignmentNewAttributes, jobs: T::Array[T::Hash[Symbol, Integer]]).void }
  def handle_errors(error, assignment_attributes:, jobs: [])
    metric_tags = CopilotSweAgentJobHelper.build_metric_tags(
      repository: current_repository,
      assignment_attributes: assignment_attributes,
      source: "agent_assignments_controller"
    )

    case error
    when CopilotAPI::NotFoundError
      GitHub.dogstats.increment("issues.copilot.assign", tags: metric_tags + ["status:failure", "reason:not_found"])
      render json: {
        error: "The agent was not found in this repository.",
        jobs: jobs
      }, status: :forbidden
    when CopilotAPI::UnauthorizedError
      GitHub.dogstats.increment("issues.copilot.assign", tags: metric_tags + ["status:failure", "reason:unauthorized"])
      render json: {
        error: "Please check that you have permission to assign issues in the target repository.",
        jobs: jobs
      }, status: :forbidden
    else
      if CopilotSweAgentJobHelper.timeout_error?(error)
        GitHub.dogstats.increment("issues.copilot.assign", tags: metric_tags + ["status:failure", "reason:timeout"])
        render json: {
          error: "Failed to assign the agent after multiple retries. Please try again later.",
          jobs: jobs
        }, status: :gateway_timeout
      else
        GitHub.dogstats.increment("issues.copilot.assign", tags: metric_tags + ["status:failure", "reason:internal"])
        Failbot.report(error, {
          app: "github",
          feature: "issues_copilot_assign",
          context: "agent_assignments_controller",
          "gh.issue.numbers": params[:issue_ids]&.map(&:to_i),
          "gh.user.id": current_user&.id,
        })
        render json: {
          error: "Something went wrong while assigning the agent. Please try again later, or contact support if the problem persists.",
          jobs: jobs
        }, status: :internal_server_error
      end
    end
  end
end
