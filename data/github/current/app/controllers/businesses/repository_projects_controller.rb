# typed: true
# frozen_string_literal: true

class Businesses::RepositoryProjectsController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  def update
    allowed = params[:repository_projects_allowed]&.to_s
    validate_setting value: allowed

    message = ""
    case allowed
    when "enabled"
      this_business.enable_repository_projects(actor: current_user, force: true)
      message = "Projects are enabled for all repositories for this enterprise."
    when "disabled"
      this_business.disable_repository_projects(actor: current_user, force: true)
      message = "Projects are disabled for all repositories for this enterprise."
    when "no_policy"
      this_business.clear_repository_projects_setting(actor: current_user)
      message = "Repository projects policy was removed. Individual organizations may enable or disable repository projects."
    end

    redirect_to settings_projects_enterprise_path(this_business), notice: message
  end
end
