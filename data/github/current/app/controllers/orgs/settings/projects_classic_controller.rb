# typed: true
# frozen_string_literal: true

class Orgs::Settings::ProjectsClassicController < Orgs::Controller
  before_action :login_required
  before_action :ensure_current_organization
  before_action :organization_admin_required

  def update
    args = params.require(:organization).permit(:repository_projects_enabled)

    if args[:repository_projects_enabled] == "1"
      current_organization.enable_repository_projects(actor: current_user)
    else
      current_organization.disable_repository_projects(actor: current_user)
    end

    flash[:notice] = "Projects (classic) settings updated for this organization."

    redirect_to :back
  end
end
