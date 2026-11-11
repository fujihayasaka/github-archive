# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::DeployKeysController < StafftoolsController
  before_action :ensure_repo_exists

  def destroy
    key = current_repository.public_keys.find_by_id(params[:deploy_key_id].presence&.to_i)

    unless key
      flash[:error] = "The deploy key could not be found."
      return redirect_to deploy_keys_stafftools_repository_path(current_repository.owner_display_login, current_repository)
    end

    if key.destroy_with_explanation(:removed_by_staff)
      flash[:notice] = "The deploy key has been deleted."
    else
      flash[:error] = "Error deleting the deploy key."
    end

    redirect_to deploy_keys_stafftools_repository_path(current_repository.owner_display_login, current_repository)
  end
end
