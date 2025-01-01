# typed: true
# frozen_string_literal: true

class Stafftools::DmcaTakedownsController < StafftoolsController
  before_action :dotcom_required
  before_action :ensure_repo_exists

  def create
    url = params["takedown_url"]

    if current_repository.access.dmca_takedown(current_user, url)
      flash[:notice] = "Repository has been enqueued to be taken down."
      redirect_back_with_anchor("#danger-zone") and return
    else
      flash[:error] = current_repository.errors[:base].to_sentence
    end

    redirect_to :back
  end

  def destroy
    if !current_repository.access.dmca?
      flash[:notice] = "No takedown notice on file"
    elsif current_repository.enable_access(current_user)
      flash[:notice] = "Takedown removed"
    else
      flash[:error] = "Failed to remove DMCA takedown"
    end

    redirect_to :back
  end
end
