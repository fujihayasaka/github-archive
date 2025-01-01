# typed: strict
# frozen_string_literal: true

class Issues::AgentAssignmentsController < IssuesController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  # Based on the maximum number of issues on an issues#index page
  MAX_PAGE_SIZE = 100

  before_action :login_required
  before_action :require_issues_copilot_cross_repo_assign_enabled
  before_action :try_parse_json_params, only: [:create]
  before_action :validate_assignment_params, only: [:create]

  allow_verified_fetch only: [:create]

  # Custom exception classes for better error handling
  class RepositoryNotFoundError < StandardError; end
  class BotAccessError < StandardError; end
  class BotNotAssignableError < StandardError; end
  class CopilotSweAgentDisabledError < StandardError; end

  TIMEOUT_MESSAGE = "Took too long to assign Copilot. Please try again."

  UNAVAILABLE_MESSAGE = "Assigning issues is currently unavailable. Please try again later."

  sig { void }
  def create
    use_async = FeatureFlag.vexi.enabled?(:cca_cross_repo_bulk_perf_improvements, current_user, current_repository, current_repository.owner, default: false)

    assignment_attributes = Issues::AgentAssignmentNewAttributes.new(
        issue_ids: params[:issue_ids].map(&:to_i),
        repo_name_with_owner: params[:repo_name_with_owner],
        base_ref: params[:base_ref],
        custom_instructions: params[:custom_instructions]
      )

    # Load issues scoped to current_repository and validate readability/assignability
    issues = load_issues_for_numbers(assignment_attributes.issue_ids)
    not_found = assignment_attributes.issue_ids - issues.map(&:number)
    unless not_found.empty?
      render json: { error: "Issue(s) not found: #{not_found.join(', ')}" }, status: :not_found
      return
    end

    actor = T.must(current_user)
    auth_promises = issues.map { |issue| issue.async_assignable_by?(actor: actor) }
    auth_results = Promise.all(auth_promises).sync
    unauthorized_issues = issues.zip(auth_results).reject { |_, can_assign| can_assign }.map { |issue, _| issue.number }

    unless unauthorized_issues.empty?
      render json: { error: "Forbidden to assign to issue(s): #{unauthorized_issues.join(', ')}" }, status: :forbidden
      return
    end

    app = T.let(Apps::Privileged.integration(:copilot_swe_agent), T.nilable(Integration))
    target_repository = Repositories.domain.by_qualified_name(assignment_attributes.repo_name_with_owner)
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

    begin
      ensure_copilot_swe_agent_is_enabled!(app, target_repo)
      ensure_copilot_swe_agent_is_enabled!(app, current_repository)
    rescue RepositoryNotFoundError
      render json: { error: "Repository not found." }, status: :not_found
      return
    rescue BotAccessError
      render json: { error: "Bot does not have access to the repository." }, status: :forbidden
      return
    rescue BotNotAssignableError
      render json: { error: "Bot cannot be assigned to issues or pull requests." }, status: :forbidden
      return
    rescue CopilotSweAgentDisabledError
      render json: { error: "Copilot coding agent is not enabled in this repository." }, status: :forbidden
      return
    end

    copilot = app&.bot
    unless copilot.present?
      render json: { error: "Copilot was not found" }, status: :forbidden
      return
    end

    assignment_results = Issues.domain.copilot.assign_copilot_to_issues(
      actor: actor,
      issues: issues,
      assignment_attributes: assignment_attributes,
      user_session: user_session,
      use_async: use_async
    )

    jobs = assignment_results[:jobs]

    if assignment_results[:any_request_timed_out]
      render json: { error: TIMEOUT_MESSAGE, jobs: jobs }, status: :gateway_timeout
      return
    end

    if assignment_results[:internal_errors].any?
      render json: { error: assignment_results[:internal_errors].join(", "), jobs: jobs }, status: :internal_server_error
      return
    end

    if assignment_results[:save_assignees_errors].any?
      render json: { error: assignment_results[:save_assignees_errors].join(", "), jobs: jobs }, status: :unprocessable_entity
      return
    end

    if assignment_results[:job_creation_errors].any?
      render json: { error: assignment_results[:job_creation_errors].join(", "), jobs: jobs }, status: :unprocessable_entity
      return
    end

    render json: { jobs: jobs }, status: :ok
  end

  private

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
      raise ArgumentError, "can't assign copilot to more than #{MAX_PAGE_SIZE} issues at a time"
    end
  end

  sig { void }
  def require_issues_copilot_cross_repo_assign_enabled
    render_404 unless is_issues_copilot_cross_repo_assign_enabled?
  end

  sig { returns(T::Boolean) }
  def is_issues_copilot_cross_repo_assign_enabled?
    (current_repository.copilot_swe_agent_enabled?(current_user) || false) &&
    (current_user&.feature_flag_enabled?(:issues_copilot_cross_repo_assign, default: false) || false)
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

      if params[:repo_name_with_owner].blank?
        errors << "repo_name_with_owner can't be blank"
      end
      if params[:base_ref].blank?
        errors << "base_ref can't be blank"
      end
    end

    # Return validation errors if any
    unless errors.empty?
      render json: {
        error: errors.join(", ")
      }, status: :unprocessable_entity
    end
  end

  sig { params(numbers: T::Array[Integer]).returns(T::Array[Issue]) }
  def load_issues_for_numbers(numbers)
    return [] if numbers.empty?
    # Use reading role and scoped to current repository for safety
    ActiveRecord::Base.connected_to(role: :reading) do
      current_repository.issues.where(number: numbers).to_a
    end
  end

end
