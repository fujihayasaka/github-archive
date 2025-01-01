# typed: true
# frozen_string_literal: true

class Businesses::ProjectsController < Businesses::BusinessController

  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :projects_new_enabled_flag_required, only: [:update_members_can_change_project_visibility, :update_projects_automation_enabled]
  before_action :business_full_plan_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index]

  def index
    view = create_view_model(
      Businesses::Settings::ProjectsView,
      business: this_business,
      params: params
    )
    render "businesses/settings/projects", locals: { view: view }
  end

  def update_organization_projects_allowed # rubocop:todo GitHub/UseRestfulActions
    allowed = params[:organization_projects_allowed]&.to_s
    validate_setting value: allowed

    message = ""
    case allowed
    when "enabled"
      this_business.enable_organization_projects(actor: current_user, force: true)
      message = "Projects are enabled for all organizations for this enterprise."
    when "disabled"
      this_business.disable_organization_projects(actor: current_user, force: true)
      message = "Projects are disabled for all organizations for this enterprise."
    when "no_policy"
      this_business.clear_organization_projects_setting(actor: current_user)
      message = "Projects policy was removed. Individual organizations may enable or disable projects."
    end

    redirect_to settings_projects_enterprise_path(this_business), notice: message
  end

  def update_members_can_change_project_visibility # rubocop:todo GitHub/UseRestfulActions
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

  def update_projects_automation_enabled # rubocop:todo GitHub/UseRestfulActions
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

  def update_repository_projects_allowed # rubocop:todo GitHub/UseRestfulActions
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

  private def projects_new_enabled_flag_required
    render_404 unless GitHub.projects_new_enabled?
  end
end
