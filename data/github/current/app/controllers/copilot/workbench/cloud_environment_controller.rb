# typed: true
# frozen_string_literal: true

class Copilot::Workbench::CloudEnvironmentController < AbstractRepositoryController

  include ApplicationController::VerifiedFetchDependency

  prepend_around_action only: :create

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::Repositories,
  ApplicationRecord::Collab,
  ApplicationRecord::Configurations,
  ApplicationRecord::IssuesPullRequests,
  ApplicationRecord::Spokes,
  ApplicationRecord::Billing,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Copilot,
  only: [:show]

  before_action :require_feature_access
  before_action :login_required
  # Add Validation To Ensure Usage Allowed

  allow_verified_fetch only: [:create, :show]

  def create
    operation = Codespaces::AsyncOperation.create!(user: current_user, operation: :create_codespace)
    request.env["codespaces.async_operation_created"] = true
    force_create = begin
      !!(GitHub::JSON.parse(T.must(request).body.read)["force_create"])
    rescue Yajl::ParseError, NoMethodError
      ActiveModel::Type::Boolean.new.cast(params.fetch(:force_create, false))
    end

    vscs_target = Codespaces::Vscs.default_target
    if current_user.feature_enabled?(:copilot_workbench_enable_ppe_cloud_environments)
      vscs_target = :ppe
    end

    # Try to find existing cloudspace
    if params[:spark_id]
      workbench = ::Workbench.load_workbench(current_user.id, params[:spark_id])
      cloudspace_id = workbench&.dig("cloudspace_id")
      if cloudspace_id && !force_create
        cloudspace = current_user.codespaces.visible_to_ephemeral_cloud_environments(current_user).find_by(guid: cloudspace_id, vscs_target: vscs_target)
        if cloudspace && !cloudspace.failed? && !cloudspace.stuck_provisioning? && !cloudspace.suspended?
          env = fetch_environment!(cloud_environment: cloudspace)
          if env.present? && !env.empty?
            render json: {
              cloud_environment: {
                guid: cloudspace&.guid,
                state: cloudspace&.state,
              },
              environment_data: env,
            }
            return
          end
        end
      end
    end

    location = Codespaces::GetRegionForUser.call(
      user: current_user,
      repository: current_repository,
      client: :dotcom,
      vscs_target: vscs_target
    )

    # Create new cloudspace if we didn't find an existing one
    ActiveRecord::Base.connected_to(role: :writing) do
      result = begin
          # Determine if we want to use a new COPILOT_WORKSPACE_ID for this scenario
          CloudEnvironments::Public.create_ephemeral(
            attributes: build_attributes(location: location, vscs_target: vscs_target),
            environment_options: environment_options,
            stats_tagger: stats_tagger(location: location, vscs_target: vscs_target),
            entry_point: nil,
            operation: operation
          )
        end

      unless result.cloud_environment
        GitHub.logger.error("NilCloudspaceForWorkbench")
        operation.mark_as_failed(failure_reason: "NilCloudspaceForWorkbench")
        return deliver_error! 404, message: "Could not create a cloud environment"
      end

      cloudspace = result.cloud_environment
      environment = result.env

      if workbench
        workbench["cloudspace_id"] = cloudspace.guid
        ::Workbench.save_workbench(current_user.id, params[:spark_id], JSON.dump(workbench))
      end

      render json: {
        cloud_environment: {
          guid: cloudspace&.guid,
          state: cloudspace&.state,
        },
        environment_data: environment&.json, # Returns the complete environments response without any filtering
      }
    end
  # TODO: These rescue blocks were taken from workspace_editor/cloud_environments_controller.rb determine if all are relevant
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
      }
    elsif current_cloud_environment.failed? || current_cloud_environment.stuck_provisioning?
      head :service_unavailable
    else
      # Render current state
      render json: {
        cloud_environment: current_cloud_environment.as_json(root: "cloud_environment", only: %i[guid state])["cloud_environment"],
        environment_data: current_cloud_environment.environment_data, # Returns the cached environment data (does not include connection)
      }
    end
  end

  private

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    self
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless current_repository # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    Codespaces::RepositoryPolicy.async_with_prefill(current_user, current_repository).sync.billable_owner || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def require_feature_access
    render_404 unless current_user&.feature_enabled?(:copilot_workbench)
  end

  def deliver_error!(status, message:)
    render json: { error: message }, status: status
  end

  memoize def current_cloud_environment
    return unless params[:identifier] && logged_in?

    current_user.codespaces.visible_to_ephemeral_cloud_environments(current_user).find_by(guid: params[:identifier]) ||
      current_user.codespaces.visible_to_ephemeral_cloud_environments(current_user).find_by(name: params[:identifier])
  end

  def ready_to_connect?
    current_cloud_environment&.provisioned? &&
      Codespaces::Vscs::State::CONSUMING_COMPUTE_STATES.include?(current_cloud_environment.environment_data.state) &&
      Codespaces::Vscs::State::QUEUED != current_cloud_environment.environment_data.state
  end

  def build_attributes(location:, vscs_target:)
    ref = current_repository.default_branch
    billable_owner = Codespaces::RepositoryPolicy.async_with_prefill(current_user, current_repository).sync.billable_owner

    default_sku = Codespaces::Skus.default_sku(
      repository: current_repository,
      owner: current_user,
      location: location,
      ref: ref,
      billable_owner: billable_owner,
      vscs_target: vscs_target
    )&.name&.to_s

    ref_for_oid = Codespaces::GetTargetRef.call(repository: current_repository, name_or_oid: ref)
    oid = ref_for_oid&.target_oid
    devcontainer_path = Codespaces::DevContainer.get_default_path(current_repository, oid)

    plan_attrs = {
      location: location,
      vscs_target: vscs_target,
    }
    plan = Codespaces::Plan.for!(**plan_attrs)

    {
      owner: current_user,
      repository_id: current_repository.id,
      ref: ref,
      oid: oid,
      billable_owner: billable_owner,
      vscs_target: vscs_target,
      retention_period_minutes: retention_period_minutes,
      sku_name: default_sku,
      location: location,
      plan: plan,
      devcontainer_path: devcontainer_path,
    }
  end

  def environment_options
    # Auto shutdown set to 30 minutes, adjust later based on requirements
    {
      autoShutdownDelayMinutes: 30,
      fileSyncerWithBridge: true
    }
  end

  def stats_tagger(location:, vscs_target:)
    CloudEnvironments::StatsTagger.new(
       vscs_target: vscs_target,
       user: current_user,
       location: location,
     )
  end

  def retention_period_minutes
    # We delete on shutdown anyway but just in case
    1.day.in_minutes.to_i
  end

  def fetch_environment!(cloud_environment:)
    return unless cloud_environment&.guid
    Codespaces::VscsClient.for_codespace(cloud_environment).fetch_environment!(cloud_environment.guid)
  rescue Codespaces::Client::BadResponseError => e
    # If there is an error from the service we will ignore it and provision a new cloudspace
    nil
  end
end
