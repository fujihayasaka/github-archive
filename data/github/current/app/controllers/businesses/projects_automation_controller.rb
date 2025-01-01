# typed: true
# frozen_string_literal: true

class Businesses::ProjectsAutomationController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :projects_new_enabled_flag_required
  before_action :business_full_plan_required

  def update
    allowed = params[:projects_automation_enabled]&.to_s
    validate_setting value: allowed

    message = ""
    case allowed
    when "enabled"
      GitHub.enable_projects_automation(actor: current_user)
      message = "Project workflow automation is enabled for all projects for this enterprise."
    when "disabled"
      GitHub.disable_projects_automation(actor: current_user)
      message = "Project workflow automation is disabled for all projects for this enterprise."
    end
    redirect_to settings_projects_enterprise_path(this_business), notice: message
  end

  private

  def projects_new_enabled_flag_required
    render_404 unless GitHub.projects_new_enabled?
  end
end
