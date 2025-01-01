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
    only: [:index, :show]

  sig { void }
  def create
    workbench = JSON.parse(request.raw_post)

    uuid = SecureRandom.uuid
    workbenches = ::Workbench.load_workbenches(current_user.id)
    workbenches << { id: uuid, name: workbench["name"] }
    ::Workbench.save_workbenches(current_user.id, workbenches)

    workbench[:id] = uuid
    ::Workbench.save_workbench(current_user.id, uuid, JSON.dump(workbench))

    respond_to do |format|
      format.json do
        render json: { message: "Copilot workbench created", workbench: }, status: :created
      end
    end
  end

  sig { void }
  def index
    workbenches = ::Workbench.load_workbenches(current_user.id)

    respond_to do |format|
      format.html do
        render json: workbenches
      end
      format.json do
        render json: { workbenches: workbenches }
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

    respond_to do |format|
      format.json do
        render json: workbench, status: status
      end
    end
  end

  sig { void }
  def update
    raw = request.raw_post
    ::Workbench.save_workbench(current_user.id, params[:id], raw)

    workbench = JSON.parse(raw)
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
end
