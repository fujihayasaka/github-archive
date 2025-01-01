# typed: true
# frozen_string_literal: true

class WorkspaceEditor::CloudEnvironmentController < WorkspaceEditor::ControllerBase

  include ApplicationController::VerifiedFetchDependency

  prepend_around_action :ensure_create_async_operation_created, only: :create

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    only: [:show, :permissions_check]

  before_action :require_pull, only: [:create, :show, :permissions_check]
  before_action :require_current_cloud_environment, only: :show
  before_action :ensure_usage_allowed, only: [:create, :show]

  allow_verified_fetch only: [:create, :show, :permissions_check]

  def create
    operation = Codespaces::AsyncOperation.create!(user: current_user, operation: :create_codespace)
    request.env["codespaces.async_operation_created"] = true

    location = Codespaces::GetRegionForUser.call(
      user: current_user,
      repository: current_repository,
      client: :dotcom
    )

    ActiveRecord::Base.connected_to(role: :writing) do
      result = begin
        force_create = begin
          !!(GitHub::JSON.parse(T.must(request).body.read)["force_create"])
        rescue Yajl::ParseError, NoMethodError
          ActiveModel::Type::Boolean.new.cast(params.fetch(:force_create, false))
        end
        WorkspaceEditor::Cloudspaces::Public.create_unique(
          repository_id: current_repository.id,
          owner: current_user,
          pull_request_number: pull.number,
          force_create:,
          location:,
          operation:,
        )
      end

      unless result.workspace_editor_cloudspace
        GitHub.logger.error("NilCreateResultOrCloudspaceFoundOrCreated", found: result.found?)
        operation.mark_as_failed(failure_reason: "NilCreateResultOrCloudspace")
        # We should figure out when/why this is happening. It's not clear to me why we would ever get here.
        return deliver_error! 404, message: "Could not find or create a cloud environment for the given pull request"
      end

      workspace_editor_cloudspace = result.workspace_editor_cloudspace
      cloud_environment = workspace_editor_cloudspace&.cloud_environment
      environment = result.env
      status = result.found? ? 200 : 201
      render status:, json: {
        cloud_environment: {
          guid: cloud_environment&.guid,
          state: cloud_environment&.state,
        },
        environment_data: environment&.json, # Returns the complete environments response without any filtering
      }
    end
  # TODO: We'll have to rework these errors to be for the newly decoupled Workspace Editor Cloudspaces or whatever we call them
  rescue ActiveModel::ValidationError => e
    operation&.mark_as_ended
    status = 400
    if e.model.errors.include?(:usage)
      status = 402
    end
    deliver_error! status, message: e.model.errors.full_messages.join(", ")
  rescue ActiveRecord::RecordInvalid => e
    operation&.mark_as_ended
    status = 400
    if e.record.errors.include?(:usage)
      status = 402
    end
    deliver_error! status, message: e.record.errors.full_messages.join(", ")
  rescue Codespaces::Client::BadResponseError => e
    if e.unprocessable_entity?
      operation&.mark_as_ended
    else
      operation&.mark_as_failed(failure_reason: e.status)
      Codespaces::ErrorReporter.report(e)
    end
    deliver_error! e.status, message: e.message
  rescue WorkspaceEditor::Cloudspaces::FeatureDisabledError => e
    operation&.mark_as_ended
    deliver_error! 403, message: e.message
  rescue Codespaces::CopilotWorkspaceFeatureDisabledError => e
    operation&.mark_as_ended
    deliver_error! 403, message: e.message
  rescue Codespaces::Plan::PlanNotFoundForLocation => e
    operation&.mark_as_failed(failure_reason: e)
    Codespaces::ErrorReporter.report(e) unless GitHub.flipper[:codespaces_automated_testing].enabled?(current_user)
    deliver_error! 400, message: e.message
  rescue Codespaces::VscsClient::SecretDataTooLarge => e
    operation&.mark_as_ended
    deliver_error! 422, message: e.message
  rescue Codespaces::ConcurrencyLimitError => e
    operation&.mark_as_ended
    deliver_error! 400, message: e.message
  rescue Codespaces::CopilotWorkspaceConcurrencyLimitError => e
    operation&.mark_as_ended
    deliver_error! 400, message: e.message
  rescue Codespaces::RateLimitError => e
    operation&.mark_as_ended
    deliver_error! 429, message: e.message
  rescue Codespaces::DevContainer::ReadError => e
    operation&.mark_as_ended
    deliver_error! 400, message: e.message
  rescue Codespaces::DevContainer::ParseError
    operation&.mark_as_ended
    deliver_error! 400, message: "Provided devcontainer.json cannot be parsed to valid JSON"
  rescue Codespaces::VscsClient::TierCapacityUnavailableError => e
    operation&.mark_as_failed(failure_reason: e)
    Codespaces::ErrorReporter.report(e) unless GitHub.flipper[:codespaces_automated_testing].enabled?(current_user)
    deliver_error! 400, message: e.message
  rescue Codespaces::Locations::Region::UnavailableError => e
    operation&.mark_as_ended
    deliver_error! 503, message: e.message
  rescue Codespaces::Locations::Region::InvalidError => e
    operation&.mark_as_ended
    deliver_error! 400, message: e.message
  rescue Codespaces::Locations::Geo::InvalidError => e
    operation&.mark_as_ended
    deliver_error! 400, message: e.message
  rescue Codespaces::Tokens::Error => e
    if e.message.include?("repository_not_found")
      operation&.mark_as_ended
      deliver_error! 403, message: "The repository could not be found."
    else
      operation&.mark_as_failed(failure_reason: e)
      deliver_error! 400, message: e.message
    end
  rescue => e # rubocop:disable Lint/GenericRescue
    operation&.mark_as_failed(failure_reason: e)
    raise
  end

  def show
    if ready_to_connect?
      env = Codespaces::VscsClient.for_codespace(current_cloud_environment).fetch_environment!(current_cloud_environment.guid)
      render json: {
        cloud_environment: current_cloud_environment.as_json(root: "cloud_environment", only: %i[guid state])["cloud_environment"],
        environment_data: env, # Pass through the response from the Codespaces service
        # TODO: Include user editor settings from Codespaces::Settings
      }
    elsif current_cloud_environment.failed? || current_cloud_environment.stuck_provisioning?
      head :service_unavailable
    else
      # Render current state
      render json: {
        cloud_environment: current_cloud_environment.as_json(root: "cloud_environment", only: %i[guid state])["cloud_environment"],
        environment_data: current_cloud_environment.environment_data, # Returns the cached environment data (does not include connection)
        # TODO: Include user editor settings from Codespaces::Settings?
      }
    end
  end

  def permissions_check
    if current_dev_container.present?
      allow_permissions_url = current_dev_container.permissions_approval_link(current_ref) if current_dev_container.permissions_need_allowance?

      render json: {
        accepted: current_dev_container.permissions_accepted?,
        allowPermissionsUrl: allow_permissions_url,
      }
    else
      render json: {
        accepted: true,
        allowPermissionsUrl: nil,
      }
    end

  rescue Codespaces::DevContainer::ReadError
    deliver_error! 404, message: "Could not read the devcontainer.json file"
  end

  private

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    # This is what we do when we don't have a current_codespace in ApplicationController::CodespaceDependency...
    self
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless current_repository # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    Codespaces::RepositoryPolicy.async_with_prefill(current_user, current_repository).sync.billable_owner || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def deliver_error!(status, message:)
    render json: { error: message }, status: status
  end

  def require_pull
    render json: { error: "Pull request not found" }, status: :not_found unless pull
  end

  memoize def pull
    PullRequests::PullRequestAccessor.new.by_number(repository_id: current_repository.id, number: params[:id].to_i)
  rescue GH::Errors::ObjectNotFound
    nil
  end

  memoize def current_cloud_environment
    return unless params[:identifier] && logged_in?

    current_user.codespaces.visible_to_workspace_editor_cloud_environments(current_user, repository: current_repository).find_by(guid: params[:identifier]) ||
      current_user.codespaces.visible_to_workspace_editor_cloud_environments(current_user, repository: current_repository).find_by(name: params[:identifier])
  end

  def ready_to_connect?
    current_cloud_environment.provisioned? &&
      Codespaces::Vscs::State::CONSUMING_COMPUTE_STATES.include?(current_cloud_environment.environment_data.state) &&
      Codespaces::Vscs::State::QUEUED != current_cloud_environment.environment_data.state
  end

  def require_feature_access
    render_404 unless current_user&.workspace_editor_preview_enabled?(repository: current_repository)
  end

  def require_current_cloud_environment
    render_404 unless current_cloud_environment
  end

  def ensure_create_async_operation_created(&block)
    ensure_async_operation_created(:create_codespace, &block)
  end

  def ensure_start_async_operation_created(&block)
    ensure_async_operation_created(:start_codespace, &block)
  end

  def ensure_async_operation_created(operation)
    yield
  rescue => e # rubocop:disable Lint/GenericRescue
    if !request.env["codespaces.async_operation_created"]
      codespaces_automated_testing = begin
        current_user.feature_enabled?(:codespaces_automated_testing)
      rescue # rubocop:disable Lint/GenericRescue
        false
      end
      if ignored_async_error?(e)
        Codespaces::AsyncOperation.report_ended(operation:, codespaces_automated_testing:)
      else
        Codespaces::AsyncOperation.report_failure(operation:, codespaces_automated_testing:, failure_reason: e)
      end
    end
    raise
  end

  def ignored_async_error?(e)
    # ActionController::InvalidAuthenticityToken is a Rails security mechanism and does not indicate anything wrong with the service itself so we do not
    # count it as a failure. Codespaces::AsyncOperation::PendingError is a normal safeguard to prevent starting codespaces while their storage
    # is being updated and similarly does not indicate a failure.
    [ActionController::InvalidAuthenticityToken, Codespaces::AsyncOperation::PendingError].any? { |klass| e.instance_of? klass }
  end

  memoize def current_dev_container
    ref_for_oid = Codespaces::GetTargetRef.call(repository: current_repository, name_or_oid: current_ref)
    oid = ref_for_oid&.target_oid
    devcontainer_path = params[:devcontainer_path] || Codespaces::DevContainer.get_default_path(current_repository, oid)

    dc = Codespaces::DevContainer.new(
      repository: current_repository,
      oid: pull.head_sha,
      filepath: devcontainer_path,
      user: current_user
    )
    if dc.exists?
      dc
    else
      nil
    end
  end

  memoize def current_ref
    # Fetch the default devcontainer path since users can't choose which one to use
    params[:ref] || current_repository.default_branch
  end

  def ensure_usage_allowed
    owner = current_user
    repository = current_repository
    billable_owner = Codespaces::RepositoryPolicy.async_with_prefill(owner, repository).sync.billable_owner

    usage = Codespaces::AccessChecker.new(billable_owner, user: owner, repository: repository, workspace_editor_cloudspace: true)

    usage_result = usage.run_check(
      sku_name: nil,
      dev_container: current_dev_container,
    )

    return if usage_result.allowed?

    deliver_error! 403, message: "You’ve reached your codespaces usage limit for the Copilot Workspace for PRs Public Preview"

  rescue Codespaces::DevContainer::ReadError
    deliver_error! 404, message: "Could not read the devcontainer.json file"
  end
end
