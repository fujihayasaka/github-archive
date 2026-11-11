# typed: strict
# frozen_string_literal: true

class Copilot::WorkbenchController < Copilot::Workbench::AbstractWorkbenchController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index, :show]

  sig { void }
  def index
    favorites = ::Workbench.load_favorites(current_user.id).to_set
    workbenches = ::Workbench.load_workbenches(current_user.id)
    codespaces_by_id = current_user.codespaces.visible_to_workbench_cloud_environments(current_user).index_by(&:id)

    # Preload runtime apps to avoid N+1 queries
    permanent_names = workbenches.map { |w| w[:runtime][:app][:permanentName] }.compact.uniq
    runtime_apps_by_name = Spark::RuntimeApp.where(permanent_name: permanent_names).index_by(&:permanent_name)

    # Preload deploys to avoid N+1 queries
    deploys_by_app_id = Spark::RuntimeAppDeploy.where.not(display_name: "spark-preview").where(runtime_app_id: runtime_apps_by_name.values.map(&:id)).group_by(&:runtime_app_id)

    # Preload the owner for all these runtime apps to avoid N+1 queries
    runtime_app_owner = runtime_apps_by_name.values.first&.runtime_app_owner

    workbenches.each do |workbench|
      workbench[:favorite] = favorites.include?(workbench[:id])

      if codespace = codespaces_by_id[workbench[:cloudspace_id]]
        workbench[:cloudspace_active] = codespace.consuming_compute?
        workbench[:cloudspace_name] = codespace.name
        workbench[:cloudspace_guid] = codespace.guid
        workbench[:cloudspace_last_used_at] = codespace.last_used_at.iso8601
      end

      runtime_app = runtime_apps_by_name[workbench[:runtime][:app][:permanentName]]
      last_deploy = deploys_by_app_id[runtime_app.id]&.last if runtime_app
      if last_deploy
        deploy = {
          createdAt: last_deploy.created_at,
          deployLogin: runtime_app_owner.deploy_login,
          displayName: last_deploy.display_name,
          domainBase: runtime_app_owner.deployment_domain_base,
          revision: last_deploy.revision,
        }
        workbench[:deploy] = deploy
      end
    end

    respond_to do |format|
      format.json do
        render json: { workbenches: }
      end
    end
  end

  sig { void }
  def show
    status = :ok
    workbench = ::Workbench.load_workbench(current_user.id, params[:id])
    if workbench.nil?
      status = :not_found
      workbench = {}
    else
      if current_user&.feature_flag_enabled?(:copilot_spark_workbench_deploy_info, default: false)
        runtime_app = T.must(Spark::RuntimeApp.find_by(permanent_name: workbench.dig(:runtime, :app, :permanentName)))
        last_deploy = runtime_app.runtime_app_deploys.where.not(display_name: "spark-preview").last
        if last_deploy
          deploy = {
            createdAt: last_deploy.created_at,
            deployLogin: runtime_app.runtime_app_owner.deploy_login,
            displayName: last_deploy.display_name,
            domainBase: runtime_app.runtime_app_owner.deployment_domain_base,
            revision: last_deploy.revision,
          }
          workbench[:deploy] = deploy
        end
      end

    end

    respond_to do |format|
      format.json do
        render json: workbench, status: status
      end
    end
  end

  sig { void }
  def update
    original_workbench = ::Workbench.load_workbench(current_user.id, params[:id])

    ::Workbench.save_workbench(current_user.id, params[:id], allowed_update_params)

    begin
      generate_friendly_name_if_missing
    rescue => e
      GitHub.logger.error("Failed to generate friendly name for workbench",
        "gh.error.message" => e.message,
        "gh.workbench.id" => params[:id],
        "gh.user.id" => current_user.id,
        "gh.request.body" => request.raw_post)
      raise # Re-throw so we don't affect the existing behavior
    end

    workbench = ::Workbench.load_workbench(current_user.id, params[:id])

    notify_aca_of_settings_change(params[:id])

    respond_to do |format|
      format.json do
        render json: workbench
      end
    end
  end

  sig { void }
  def destroy
    workbench = ::Workbench.load_workbench(current_user.id, params[:id])
    permanent_name = workbench&.dig(:runtime, :app, :permanentName)

    ::Workbench.delete_workbench(current_user.id, params[:id])

    if current_user.feature_flag_enabled?(:spark_snapshot_cleanup, default: false)
      begin
        Workbench::SnapshotBlobs.delete_container(params[:id])
      rescue => e
        GitHub.logger.error("Failed to delete Spark blob container",
          "gh.error.message" => e.message,
          "gh.workbench.id" => params[:id],
          "gh.user.id" => current_user.id
        )
      end
    end

    if current_user.feature_flag_enabled?(:spark_eyesite_scanning_cleanup, default: false) && permanent_name.present?
      begin
        Workbench::ScanningBlobClient.delete_blobs_for_app(permanent_name)
      rescue => e
        GitHub.logger.error("Error deleting Spark Eyesite Scanning blobs",
          "gh.error.message" => e.message,
          "gh.workbench.id" => params[:id],
          "gh.user.id" => current_user.id,
          "gh.app_name" => permanent_name
        )
      end
    end

    respond_to do |format|
      format.json do
        render json: { success: true }
      end
    end
  end

  private

  sig { returns(String) }
  def allowed_update_params
    values = JSON.parse(request.raw_post)

    values.slice(
      "name",
      "description",
      "currentRefinementId",
      "runtime",
      "files",
      "previousRefinements",
      "suggestions",
      "shouldGenerateInitialPrompt",
    ).to_json
  end

  sig { void }
  def generate_friendly_name_if_missing
    data = JSON.parse(request.raw_post)
    # Don't generate if we're asking for an explicit name
    if data.dig("runtime", "app", "friendlyName").blank?
      workbench = Spark::Workbench.for_uuid_string(current_user.id, params[:id])
      runtime_app = T.must(T.must(workbench).runtime_app)

      # If we have our permanent name in the friendly name, we're unset so generate a name
      if runtime_app.friendly_name.blank? || runtime_app.friendly_name == runtime_app.permanent_name
        new_name = ::SparkRuntime::Naming.generate_unique_app_name(current_user, data["name"])
        runtime_app.update!(friendly_name: new_name)
      end
    end
  end

  sig do
    params(
      uuid: String,
    ).void
  end
  def notify_aca_of_settings_change(uuid)
    workbench = Spark::Workbench.for_uuid_string(current_user.id, uuid)
    return unless workbench

    SparkRuntime::AcaInterface.notify_settings_changes(current_user, workbench)
  end

  # We override the require_feature_enabled from the abstract controller because we want this controller to still
  # return Spark data in cases where the user technically has access to Spark, but their parent organization or
  # enterprise has disabled their access.
  #
  # This can happen in cases where a user is part of the Spark preview, but the org/enterprise giving them a Copilot
  # seat has revoked access.
  sig { void }
  def require_feature_enabled
    render_404 unless current_user&.feature_flag_enabled?(:copilot_workbench, default: false) || current_user&.part_of_spark_rollout?
  end
end
