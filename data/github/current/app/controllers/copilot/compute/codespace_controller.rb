# typed: true
# frozen_string_literal: true

class Copilot::Compute::CodespaceController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  class StatsTagger < Codespaces::StatsTagger
    include CloudEnvironments::IStatsTagger
  end

  prepend_around_action :ensure_create_async_operation_created, only: :create
  prepend_around_action :ensure_start_async_operation_created, only: :start

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Copilot::Compute::CodespaceController#create",
    "Copilot::Compute::CodespaceController#start",
  ].freeze, T::Array[String])

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    ApplicationRecord::Ballast,
    only: [:show, :create, :start]

  before_action :login_required
  before_action :require_feature_enabled
  before_action :require_create_repository_selector, only: :create
  before_action :require_current_cloud_environment, only: [:show, :start]

  allow_verified_fetch only: [:create, :show, :start]

  def create
    operation = Codespaces::AsyncOperation.create!(user: current_user, operation: :create_codespace)
    request.env["codespaces.async_operation_created"] = true

    policy = Codespaces::RepositoryPolicy.async_with_prefill(current_user, repository).sync
    unless policy.can_attempt_create?
      operation.mark_as_ended
      return deliver_error! 403, message: "You do not have permission to create a codespace for this repository"
    end

    vscs_target = Codespaces::Vscs.default_target
    location = Codespaces::GetRegionForUser.call(
      user: current_user,
      repository: repository,
      client: :dotcom,
      vscs_target: vscs_target,
    )

    git_ref = if pull
      Codespaces::GetTargetRef.call(repository: repository, name_or_oid: pull.tracking_ref_name)
    elsif requested_pull_request_number
      # PR number was provided but not found
      operation.mark_as_ended
      return deliver_error! 404, message: "Pull request not found"
    else
      Codespaces::GetTargetRef.call(repository: repository, name_or_oid: requested_branch)
    end
    unless git_ref&.target_oid && git_ref&.name
      operation.mark_as_ended
      return deliver_error! 404, message: "Unable to resolve repository ref"
    end

    sku_name = requested_sku_name.presence || default_sku_name(
      location: location,
      vscs_target: vscs_target,
      billable_owner: policy.billable_owner,
      devcontainer_path: requested_devcontainer_path,
      repository: repository,
    )
    if sku_name.blank?
      operation.mark_as_ended
      return deliver_error! 400, message: "Unable to determine a machine type for this codespace"
    end

    stats_tagger = StatsTagger.new(
      location: location,
      repository: repository.id,
      vscs_target: vscs_target,
      using_default_sku: requested_sku_name.blank?,
      sku_name: sku_name,
      from_fork: repository.fork?,
      repo_empty: repository.empty?,
      owner: current_user,
      use_prebuild: Codespaces::Prebuilds.configured?(repository),
      is_workspace_editor_cloud_environment: false,
      is_copilot_agent_mode: false,
    )

    create_attributes = {
      owner: current_user,
      repository_id: repository.id,
      ref: git_ref.name,
      oid: git_ref.target_oid,
      location: location,
      sku_name: sku_name,
      plan: Codespaces::Plan.for!(location: location, vscs_target: vscs_target),
      billable_owner: policy.billable_owner,
      vscs_target: vscs_target,
      retention_period_minutes: 30.days.in_minutes.to_i,
    }

    if requested_devcontainer_path.present?
      create_attributes[:devcontainer_path] = requested_devcontainer_path
    end

    result = CloudEnvironments::Public.create_ephemeral(
      attributes: create_attributes,
      operation: operation,
      stats_tagger: stats_tagger,
      environment_options: { fileSyncerWithBridge: true }, # This gets SSH installed. TODO: create a specific flag for it later
      entry_point: :copilot_compute_codespace_create,
    )

    cloud_environment = result.cloud_environment
    environment = result.env
    render status: :created, json: {
      cloud_environment: {
        guid: cloud_environment&.guid,
        state: cloud_environment&.state,
      },
      environment_data: environment&.json,
    }
  rescue ActiveModel::ValidationError => e
    operation&.mark_as_ended
    deliver_error! 400, message: e.model.errors.full_messages.join(", ")
  rescue ActiveRecord::RecordInvalid => e
    operation&.mark_as_ended
    deliver_error! 400, message: e.record.errors.full_messages.join(", ")
  rescue Codespaces::Client::BadResponseError => e
    if e.unprocessable_entity?
      operation&.mark_as_ended
    else
      operation&.mark_as_failed(failure_reason: e.status)
      Codespaces::ErrorReporter.report(e)
    end
    deliver_error! e.status, message: e.message
  rescue Codespaces::Plan::PlanNotFoundForLocation => e
    operation&.mark_as_failed(failure_reason: e)
    deliver_error! 400, message: e.message
  rescue Codespaces::ConcurrencyLimitError => e
    operation&.mark_as_ended
    deliver_error! 400, message: e.message
  rescue Codespaces::RateLimitError => e
    operation&.mark_as_ended
    deliver_error! 429, message: e.message
  rescue Codespaces::Locations::Region::UnavailableError => e
    operation&.mark_as_ended
    deliver_error! 503, message: e.message
  rescue Codespaces::Locations::Region::InvalidError, Codespaces::Locations::Geo::InvalidError => e
    operation&.mark_as_ended
    deliver_error! 400, message: e.message
  rescue Codespaces::Tokens::Error => e
    operation&.mark_as_failed(failure_reason: e)
    deliver_error! 400, message: e.message
  rescue => e
    operation&.mark_as_failed(failure_reason: e)
    raise
  end

  def show
    if ready_to_connect? || current_cloud_environment&.suspended?
      env = Codespaces::VscsClient.for_codespace(current_cloud_environment).fetch_environment!(current_cloud_environment.guid)
      render json: {
        cloud_environment: current_cloud_environment.as_json(root: "cloud_environment", only: %i[guid state])["cloud_environment"],
        environment_data: env,
      }
    elsif current_cloud_environment.failed? || current_cloud_environment.stuck_provisioning?
      head :service_unavailable
    else
      render json: {
        cloud_environment: current_cloud_environment.as_json(root: "cloud_environment", only: %i[guid state])["cloud_environment"],
        environment_data: current_cloud_environment.environment_data,
      }
    end
  end

  def start # rubocop:todo GitHub/UseRestfulActions
    operation = begin
      Codespaces::AsyncOperation.ensure_no_blocking_pending!(current_cloud_environment)
      Codespaces::AsyncOperation.create!(codespace: current_cloud_environment, operation: :start_codespace)
    rescue Codespaces::AsyncOperation::PendingError => e
      request.env["codespaces.async_operation_created"] = true
      return deliver_error! 422, message: e.message
    end
    request.env["codespaces.async_operation_created"] = true

    if Codespaces::Policy.codespace_user_spammy?(current_cloud_environment)
      operation.mark_as_ended
      return deliver_error! 403, message: "Forbidden"
    end

    if current_cloud_environment.provisioning?
      operation.mark_as_ended
      return deliver_error! 409, message: "This codespace is still being provisioned, please try again in a few seconds."
    end

    Codespaces::Start.call(
      current_cloud_environment,
      user: current_user,
      cap_filter: cap_filter,
      entry_point: :copilot_compute_codespace_start,
      operation: operation,
    )

    render json: {
      cloud_environment: current_cloud_environment.as_json(root: "cloud_environment", only: %i[guid state])["cloud_environment"],
      environment_data: current_cloud_environment.environment_data,
    }
  rescue ActiveModel::ValidationError => e
    operation&.mark_as_ended
    status = if e.model.errors.any? { |err| err.type == :billing }
      402
    elsif e.model.errors.any? { |err| err.type == :policy }
      403
    else
      422
    end
    deliver_error! status, message: e.model.errors.full_messages.join(", ")
  rescue Codespaces::Client::BadResponseError => e
    if e.unprocessable_entity?
      operation&.mark_as_ended
    else
      operation&.mark_as_failed(failure_reason: e.status)
      Codespaces::ErrorReporter.report(e)
    end
    message, status = if e.error_codes.include?(Codespaces::VscsClient::ENVIRONMENT_NOT_SHUTDOWN_ERROR_CODE)
      ["Codespace is already running", 409]
    else
      [e.error_body.to_s, 400]
    end
    deliver_error! status, message:
  rescue Codespaces::ConcurrencyLimitError => e
    operation&.mark_as_ended
    deliver_error! 400, message: e.message
  rescue Codespaces::RateLimitError => e
    operation&.mark_as_ended
    deliver_error! 429, message: e.message
  rescue Codespaces::AsyncOperation::PendingError => e
    operation&.mark_as_ended
    deliver_error! 422, message: e.message
  rescue Codespaces::VscsClient::TierCapacityUnavailableError => e
    operation&.mark_as_failed(failure_reason: e)
    Codespaces::ErrorReporter.report(e)
    deliver_error! 400, message: e.message
  rescue Codespaces::Start::InaccessibleError
    operation&.mark_as_ended
    deliver_error! 404, message: "Codespace not found"
  rescue Codespaces::Client::RequestError => e
    operation&.mark_as_failed(failure_reason: e)
    raise
  rescue => e
    operation&.mark_as_failed(failure_reason: e)
    raise
  end

  private

  memoize def repository
    Repository.nwo("#{params[:user_id]}/#{params[:repository]}")
  rescue GH::Errors::ObjectNotFound, ActiveRecord::RecordNotFound
    nil
  end

  def requested_branch
    create_params[:branch].presence || repository&.default_branch
  end

  def requested_pull_request_number
    create_params[:pull_request_number].presence
  end

  memoize def pull
    return unless requested_pull_request_number && repository

    PullRequests::PullRequestAccessor.new.by_number(repository_id: repository.id, number: requested_pull_request_number.to_i)
  rescue GH::Errors::ObjectNotFound
    nil
  end

  def requested_sku_name
    create_params[:sku_name]
  end

  def requested_devcontainer_path
    create_params[:devcontainer_path].presence
  end

  def default_sku_name(location:, vscs_target:, billable_owner:, devcontainer_path:, repository:)
    Codespaces::Skus.default_sku(
      repository: repository,
      owner: current_user,
      location: location,
      billable_owner: billable_owner,
      vscs_target: vscs_target,
      devcontainer_path: devcontainer_path,
    )&.name&.to_s
  end

  def create_params
    {
      branch: params[:branch] || params[:branch_ref] || create_payload["branch"] || create_payload["branch_ref"],
      sku_name: params[:sku_name] || create_payload["sku_name"],
      devcontainer_path: params[:devcontainer_path] || create_payload["devcontainer_path"],
      pull_request_number: params[:pull_request_number] || create_payload["pull_request_number"],
    }
  end

  memoize def create_payload
    body = request&.body&.read
    request.body.rewind if request&.body&.respond_to?(:rewind)
    return {} if body.blank?

    parsed = GitHub::JSON.parse(body)
    parsed.is_a?(Hash) ? parsed : {}
  rescue Yajl::ParseError, NoMethodError
    {}
  end

  def require_create_repository_selector
    render_404 unless repository
  end

  def require_feature_enabled
    render_404 unless current_user&.feature_flag_enabled?(:copilot_cli_in_web_poc, default: false)
  end

  memoize def current_cloud_environment
    return unless params[:identifier] && logged_in?

    scope = current_user.codespaces.not_deprovisioning.only_ephemeral_cloud_environments
    policy_cache = Codespaces::MultiRepositoryPolicyCache.new(scope)
    accessible_ids = scope.select { _1.accessible?(repository_policy: policy_cache.get(_1)) }.map(&:id)
    visible = scope.where(id: accessible_ids)
    visible.find_by(guid: params[:identifier]) || visible.find_by(name: params[:identifier])
  end

  def require_current_cloud_environment
    render_404 unless current_cloud_environment
  end

  def ready_to_connect?
    current_cloud_environment&.provisioned? &&
      Codespaces::Vscs::State::CONSUMING_COMPUTE_STATES.include?(current_cloud_environment.environment_data.state) &&
      Codespaces::Vscs::State::QUEUED != current_cloud_environment.environment_data.state
  end

  def deliver_error!(status, message:)
    render json: { error: message }, status: status
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_cloud_environment || self
  end

  def target_for_conditional_access
    repo = current_cloud_environment&.repository || repository
    return :no_target_for_conditional_access unless repo # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    Codespaces::RepositoryPolicy.async_with_prefill(current_user, repo).sync.billable_owner || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def ensure_create_async_operation_created(&block)
    ensure_async_operation_created(:create_codespace, &block)
  end

  def ensure_start_async_operation_created(&block)
    ensure_async_operation_created(:start_codespace, &block)
  end

  def ensure_async_operation_created(operation)
    yield
  rescue => e
    if !request.env["codespaces.async_operation_created"]
      codespaces_automated_testing = begin
        current_user.feature_flag_enabled?(:codespaces_automated_testing, default: false)
      rescue
        false
      end

      Codespaces::AsyncOperation.report_failure(
        operation: operation,
        codespaces_automated_testing: codespaces_automated_testing,
        failure_reason: e,
      )
    end
    raise
  end
end
