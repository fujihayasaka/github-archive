# typed: true
# frozen_string_literal: true

class Stafftools::Users::Repositories::BulkPrivatizationsController < StafftoolsController
  before_action :ensure_user_not_org
  before_action :dotcom_required

  def create
    if repo_ids.present?
      this_user.public_repositories.where(id: repo_ids).each do |repo|
        repo.set_visibility(actor: current_user, visibility: "private")
      end

      flash[:notice] = "All targeted public repositories have been made private."
    else
      flash[:error] = "You must select at least 1 public repository!"
    end

    redirect_to stafftools_user_administrative_tasks_path(this_user)
  end

  private

  def repo_ids
    params.dig(:bulk_privatization, :repository_ids)
  end
end
