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
  only: [:show, :update]

  before_action :require_feature_enabled
  before_action :login_required
  before_action :ensure_spark_template_repo
  before_action :render_dev_codespace_info, if: :dev_codespace?

  allow_verified_fetch only: [:create, :show, :update]

  # find or create codespace
  def create
    operation = Codespaces::AsyncOperation.create!(user: current_user, operation: :create_codespace)
    request.env["codespaces.async_operation_created"] = true

    vscs_target = Codespaces::Vscs.default_target
    if current_user.feature_flag_enabled?(:copilot_workbench_enable_ppe_cloud_environments, default: false)
      vscs_target = :ppe
    end

    template = Codespaces::Template.for_repository(current_repository)
    template_repository = template&.repository

    branch_name = current_user.feature_flag_enabled?(:copilot_workbench_use_staging_template_branch, default: false) ? "staging" : nil

    ActiveRecord::Base.connected_to(role: :writing) do
      result = begin
        Workbench::SparkCloudspaces::Public.find_or_create(
          owner: current_user,
          repository_id: current_repository.id,
          template_repository_id: template_repository&.id,
          spark_id: params[:spark_id],
          operation: operation,
          vscs_target: vscs_target,
          branch_name: branch_name
        )
      end

      unless result.workbench_cloudspace&.cloud_environment
        GitHub.logger.error("NilCloudspaceForWorkbench")
        operation.mark_as_failed(failure_reason: "NilCloudspaceForWorkbench")
        return deliver_error! 404, message: "Could not find or create a cloud environment"
      end

      cloudspace = result.workbench_cloudspace&.cloud_environment
      environment = result.env

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
    Codespaces::ErrorReporter.report(e) unless FeatureFlag.vexi.enabled?(:codespaces_automated_testing, current_user, default: false)
    deliver_error! 400, message: e.message
  rescue Codespaces::VscsClient::SecretDataTooLarge => e
    operation&.mark_as_ended
    deliver_error! 422, message: e.message
  rescue Codespaces::ConcurrencyLimitError, Codespaces::CopilotWorkbenchConcurrencyLimitError => e
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
    Codespaces::ErrorReporter.report(e) unless FeatureFlag.vexi.enabled?(:codespaces_automated_testing, current_user, default: false)
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
  rescue => e # rubocop:disable Lint/RescueException
    operation&.mark_as_failed(failure_reason: e)
    raise
  end

  # start codespace
  def update
    operation = Codespaces::AsyncOperation.create!(codespace: current_cloud_environment, operation: :start_codespace)
    result = begin
      Workbench::SparkCloudspaces::Public.start(
        owner: current_user,
        cloudspace_guid: params[:identifier],
        repository_id: current_repository.id,
        cap_filter: cap_filter,
        operation: operation,
        entry_point: nil,
      )
    end

    cloud_environment = result&.workbench_cloudspace&.cloud_environment
    render json: {
      cloud_environment: {
        guid: cloud_environment&.guid,
        state: cloud_environment&.state,
      },
      environment_data: result.env,
    }
  rescue => e # rubocop:disable Lint/RescueException
    operation&.mark_as_failed(failure_reason: e)
    raise
  end

  # get codespace info
  def show
    if ready_to_connect? || current_cloud_environment&.suspended?
      env = Codespaces::VscsClient.for_codespace(current_cloud_environment).fetch_environment!(current_cloud_environment.guid)
      render json: {
        cloud_environment: current_cloud_environment.as_json(root: "cloud_environment", only: %i[guid state])["cloud_environment"],
        environment_data: env, # Pass through the response from the Codespaces service
      }
    elsif current_cloud_environment.nil? || current_cloud_environment.failed? || current_cloud_environment.stuck_provisioning?
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

  # regular method for easier stubbing
  def template_repo_nwo
    "github/spark-template"
  end

  def require_feature_enabled
    render_404 unless current_user&.spark_workbench_preview_enabled?
  end

  def ensure_spark_template_repo
    render_404 unless current_repository&.nwo == template_repo_nwo && current_repository&.public? # rubocop:disable GitHub/DoNotAllowNameWithOwner
  end

  # the spark template repo is public, so don't force SSO for employees. the method above verifies that the given repo is
  # being requested and that it's public.
  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def deliver_error!(status, message:)
    render json: { error: message }, status: status
  end

  memoize def current_cloud_environment
    return unless params[:identifier] && logged_in?

    current_user.codespaces.visible_to_ephemeral_cloud_environments(current_user).find_by(guid: params[:identifier]) ||
      current_user.codespaces.visible_to_workbench_cloud_environments(current_user).find_by(guid: params[:identifier])
  end

  def ready_to_connect?
    current_cloud_environment&.provisioned? &&
      Codespaces::Vscs::State::CONSUMING_COMPUTE_STATES.include?(current_cloud_environment.environment_data.state) &&
      Codespaces::Vscs::State::QUEUED != current_cloud_environment.environment_data.state
  end

  def fetch_environment!(cloud_environment:)
    return unless cloud_environment&.guid
    Codespaces::VscsClient.for_codespace(cloud_environment).fetch_environment!(cloud_environment.guid)
  rescue Codespaces::Client::BadResponseError => e
    # If there is an error from the service we will ignore it and provision a new cloudspace
    nil
  end

  def dev_codespace?
    Rails.env.development? && dev_codespace_info.present?
  end

  def render_dev_codespace_info
    render json: dev_codespace_info
  rescue => e
    GitHub.logger.error("Error parsing SPARK_DEV_CODESPACE_INFO_JSON: #{e.message}")
    deliver_error! 500, message: e.message
  end

  memoize def dev_codespace_info
    path = Rails.root.join("tmp", "codespace_info.json")
    return unless File.exist?(path)

    JSON.parse(File.read(path))
  rescue => e
    GitHub.logger.error("Error parsing SPARK_DEV_CODESPACE_INFO_JSON: #{e.message}")
    nil
  end
end
