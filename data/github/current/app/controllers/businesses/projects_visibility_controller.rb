# typed: true
# frozen_string_literal: true

class Businesses::ProjectsVisibilityController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :projects_new_enabled_flag_required
  before_action :business_full_plan_required

  def update
    setting_value = params[:members_can_change_project_visibility]&.to_s
    validate_setting value: setting_value

    message = ""
    case setting_value
    when "enabled"
      this_business.allow_members_to_change_project_visibility(actor: current_user, force: true)
      message = "Project admin members can now change project visibility in all organizations in this enterprise."
    when "disabled"
      this_business.block_members_from_changing_project_visibility(actor: current_user, force: true)
      message = "Only organization owners can change project visibility in all organizations in this enterprise."
    when "no_policy"
      this_business.clear_members_can_change_project_visibility_setting(actor: current_user)
      message = "Policy removed for project visibility change setting."
    end

    redirect_to settings_projects_enterprise_path(this_business), notice: message
  end

  private

  def projects_new_enabled_flag_required
    render_404 unless GitHub.projects_new_enabled?
  end
end
