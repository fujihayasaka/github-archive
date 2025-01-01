# typed: true
# frozen_string_literal: true

class Stafftools::RedirectsController < StafftoolsController

  before_action :ensure_repo_exists

  layout "layouts/stafftools/repository/overview"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    @redirects = current_repository.redirects
    render "stafftools/redirects/index"
  end

  def create
    location = params[:repository_redirect][:repository_name]
    redirect = current_repository.redirect_from_previous_location(location)
    if redirect.valid?
      flash[:notice] = "#{h location} now redirects to this repository."
    else
      flash[:error] = "That was an invalid location for the redirect. Try again."
    end
    redirect_to :back
  end

  def destroy
    redirect = current_repository.redirects.find(params[:id])
    redirect.destroy
    flash[:notice] = "#{h redirect.repository_name} no longer redirects to this repository."
    redirect_to :back
  end
end
