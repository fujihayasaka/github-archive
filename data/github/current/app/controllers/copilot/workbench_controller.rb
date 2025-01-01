# typed: strict
# frozen_string_literal: true

class Copilot::WorkbenchController < Copilot::Workbench::AbstractWorkbenchController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index, :show]

  sig { void }
  def index
    favorites = ::Workbench.load_favorites(current_user.id).to_set
    workbenches = ::Workbench.load_workbenches(current_user.id)
    codespaces_by_id = current_user.codespaces.visible_to_workbench_cloud_environments(current_user).index_by(&:id)

    workbenches.each do |workbench|
      workbench["favorite"] = favorites.include?(workbench["id"])

      if codespace = codespaces_by_id[workbench["cloudspace_id"]]
        workbench["cloudspace_active"] = codespace.consuming_compute?
        workbench["cloudspace_name"] = codespace.name
        workbench["cloudspace_guid"] = codespace.guid
        workbench["cloudspace_last_used_at"] = codespace.last_used_at.iso8601
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
    end

    if workbench.present? && workbench["runtime_app_id"].nil?
      runtime_app = ::SparkRuntimeApp.create_runtime_app(current_user)
      workbench["runtime_app_id"] = runtime_app[:app_id]
      ::Workbench::save_workbench(current_user.id, workbench["id"], JSON.dump(workbench))
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

    raw = request.raw_post
    ::Workbench.save_workbench(current_user.id, params[:id], raw)

    generate_friendly_name_if_missing

    workbench = ::Workbench.load_workbench(current_user.id, params[:id])

    notify_aca_of_name_change(original_workbench, workbench)

    respond_to do |format|
      format.json do
        render json: workbench
      end
    end
  end

  sig { void }
  def destroy
    ::Workbench.delete_workbench(current_user.id, params[:id])

    respond_to do |format|
      format.json do
        render json: { success: true }
      end
    end
  end

  private

  sig { void }
  def generate_friendly_name_if_missing
    data = JSON.parse(request.raw_post)
    # Don't generate if we're asking for an explicit name
    if data["friendlyName"].blank?
      workbench = Spark::Workbench.for_uuid_string(current_user.id, params[:id])
      runtime_app = T.must(T.must(workbench).runtime_app)

      # If we have our permanent name in the friendly name, we're unset so generate a name
      if runtime_app.friendly_name.blank? || runtime_app.friendly_name == runtime_app.permanent_name
        new_name = ::SparkRuntime::Naming.generate_unique_name(current_user, data["name"])
        runtime_app.update!(friendly_name: new_name)
      end
    end
  end

  sig do
    params(
      original_workbench: T.nilable(T::Hash[String, T.untyped]),
      workbench: T.nilable(T::Hash[String, T.untyped]),
    ).void
  end
  def notify_aca_of_name_change(original_workbench, workbench)
    return unless original_workbench && original_workbench["friendlyName"] &&
      workbench && workbench["friendlyName"]

    if original_workbench["friendlyName"] != workbench["friendlyName"]
      SparkRuntime::AcaInterface.notify_friendly_name_change(
        current_user,
        workbench["runtimePermanentName"],
        workbench["friendlyName"])
    end
  end
end
