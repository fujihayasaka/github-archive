# typed: strict
# frozen_string_literal: true

class Orgs::CopilotSettings::CustomModelsController < Orgs::CopilotSettings::BaseController
  extend GitHub::Memoizer

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include Orca::OrcaControllerHelper

  # Turn off CSRF for React.
  allow_verified_fetch only: [:create, :destroy, :cancel]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Orgs::CopilotSettings::CustomModelsController#create",
  ].freeze, T::Array[String])

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:index, :new]

  depends_on_clusters ApplicationRecord::Spokes,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:create, :edit]

  before_action :check_copilot_available
  before_action :feature_required
  before_action :parse_json_params, only: [:create]
  before_action :rate_limit, only: [:new, :create, :edit]
  before_action :check_pipeline_access, only: [:edit, :destroy, :cancel]

  javascript_bundle :settings
  javascript_bundle :copilot

  sig { returns(String) }
  def self.react_bundle_name
    "copilot-custom-models"
  end

  sig { void }
  def index
    pipelines = Orca::Pipeline.get_pipelines(current_organization)

    # sort the visible pipelines in descending order
    pipelines = pipelines.filter { |p| p.visible_training_type? }.sort_by(&:created_at).reverse

    latest = latest_pipeline
    latest_completed = latest_completed_pipeline

    payload = {
      adminEmail: admin_email,
      deployedPipeline: latest_completed.nil? ? nil : pipeline_details_as_json(latest_completed),
      enabled_features: feature_flags,
      hasAnyDeployed: any_deployed?,
      latestPipeline: latest.nil? ? nil : pipeline_details_as_json(latest),
      newPath: new_path,
      organization: current_organization.display_login,
      pipelines: pipelines.map { |pipeline| pipeline_item_as_json(pipeline) },
      rateLimitResetAt: rate_limit_reset_at,
      withinRateLimit: within_rate_limit?,
    }

    render_react_app(
      payload: payload,
      layout: "layouts/copilot/custom_models",
      title: "GitHub Copilot - Custom model",
    )
  end

  sig { void }
  def new
    render_react_app(
      payload: {
        adminEmail: admin_email,
        availableLanguages: available_languages,
        canCollectPrivateTelemetry: copilot_organization.private_telemetry_enabled?,
        createPath: create_path,
        enabled_features: feature_flags,
        enoughDataToTrain: current_organization.repositories.any?,
        organization: current_organization.display_login,
        policyPath: policy_path,
      },
      layout: "layouts/copilot/custom_models",
      title: "GitHub Copilot - New custom model",
    )
  end

  sig { void }
  def create
    repo_nwos = params[:repository_nwos]&.filter_map(&:presence)

    form = Orca::PipelineFormValidator.new(
      organization: current_organization,
      user: current_user,
      repository_nwos: repo_nwos,
      languages: params[:languages]&.filter_map(&:presence),
      use_private_telemetry: use_private_telemetry?
    )

    if repo_nwos.nil? && params[:pipeline_id].present? && current_pipeline.present?
      check_pipeline_access

      # Ensure none of the repos got moved between training runs
      form.repositories = T.must(current_pipeline).org_repositories
    end

    if form.valid?
      success, pipeline_id = form.enqueue_pipeline

      unless success
        render json: {
          error: "Could not connect to training service."
        }, status: :internal_server_error
        return
      end

      redirect_url = pipeline_id.present? ? show_path(pipeline_id) : index_path

      payload = {
        id: pipeline_id,
        message: "Successfully created training request",
        redirect_url: redirect_url,
      }

      render json: { payload: payload }
    else
      render json: { errors: form.errors }, status: :unprocessable_entity
    end
  end

  sig { void }
  def edit
    render_react_app(
      layout: "layouts/copilot/custom_models",
      title: "GitHub Copilot - Edit custom model",
      payload: {
        availableLanguages: available_languages,
        canCollectPrivateTelemetry: copilot_organization.private_telemetry_enabled?,
        createPath: create_path,
        enabled_features: feature_flags,
        languages: T.must(current_pipeline).languages,
        organization: current_organization.display_login,
        pipelineId: T.must(current_pipeline).pipeline_id,
        policyPath: policy_path,
        repoCount: T.must(current_pipeline).repository_count,
        repoListPath: repo_list_path(T.must(current_pipeline).pipeline_id),
        showPath: show_path(params["pipeline_id"]),
        wasPrivateTelemetryCollected: T.must(current_pipeline).private_telemetry_collected?,
      },
    )
  end

  sig { void }
  def destroy
    begin
      delete_result = Orca::Pipeline.delete_pipeline(current_user, current_organization, params["pipeline_id"])
      payload = {
        message: "Custom model was deleted from this organization.",
        result: delete_result,
        redirect_url: index_path
      }
      render json: { payload: payload }
    rescue Orca::Client::ServerError => err
      render json: { errors: "Error deleting training." }, status: :internal_server_error
    end
  end

  sig { void }
  def cancel # rubocop:todo GitHub/UseRestfulActions
    begin
      cancel_result = Orca::Pipeline.cancel_pipeline(current_user, current_organization, params["pipeline_id"])
      payload = {
        result: cancel_result,
        redirect_url: show_path(params["pipeline_id"])
      }
      render json: { payload: payload }
    rescue Orca::Client::ServerError => err
      render json: { errors: "Error cancelling training: #{err}" }, status: :internal_server_error
    end
  end

  private

  sig { returns(T::Boolean) }
  def use_private_telemetry?
    return false unless feature_enabled?(:copilot_private_telemetry_access)
    return false unless copilot_organization.private_telemetry_enabled?

    params[:private_telemetry]
  end
end
