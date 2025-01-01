# typed: true
# frozen_string_literal: true

class Spark::FavoritesController < Spark::AbstractController
  allow_verified_fetch

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  def index
    favorites = ::Workbench.load_favorites(current_user.id)
    workbenches = ::Workbench.load_workbenches(current_user.id)

    # This is so we preserve the order the user added the favorites in
    workbenches_hash = workbenches.each_with_object({}) do |workbench, result|
      result[workbench["id"]] = workbench
    end
    favorite_workbenches = favorites.map do |favorite|
      workbench = workbenches_hash[favorite]
      if workbench
        workbench["favorite"] = true
        workbench
      end
    end.compact

    respond_to do |format|
      format.json do
        render json: { workbenches: favorite_workbenches }
      end
    end
  end

  def create
    workbench = Spark::Workbench.for_uuid_string(current_user.id, params[:id])
    if workbench.nil?
      return render json: { error: "Workbench not found" }, status: :not_found
    end
    ::Workbench.save_favorite(current_user, workbench)

    respond_to do |format|
      format.json do
        render json: { message: "Favorite created" }, status: :created
      end
    end
  end

  def destroy
    workbench = Spark::Workbench.for_uuid_string(current_user.id, params[:id])
    if workbench.nil?
      return render json: { error: "Workbench not found" }, status: :not_found
    end
    ::Workbench.delete_favorite(current_user, workbench)

    respond_to do |format|
      format.json { head :no_content }
    end
  end

  private

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
