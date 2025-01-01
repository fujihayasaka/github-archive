# typed: true
# frozen_string_literal: true

class Businesses::Settings::ProjectsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :business

  def initialize(**args)
    super(args)
    @business = args[:business]
  end

  def projects_automation_form_path
    urls.update_settings_projects_automation_enterprise_path(business)
  end

  def projects_automation_button_text
    projects_automation_selected_option[:heading]
  end

  def projects_automation_select_list
    @project_automations_select_list ||= [

      {
        heading: "Enabled",
        value: "enabled",
        selected: projects_automation_value == "enabled",
      },
      {
        heading: "Disabled",
        value: "disabled",
        selected: projects_automation_value == "disabled",
      },
    ]
  end

  def projects_automation_input_value
    projects_automation_selected_option[:value]
  end

  def projects_automation_selected_option
    projects_automation_select_list.find { |s| s[:selected] }
  end

  def projects_automation_value
    if GitHub.projects_automation_enabled?
      "enabled"
    else
      "disabled"
    end
  end

  def organizations_form_path
    urls.update_settings_organization_projects_enterprise_path(business)
  end

  def organizations_button_text
    organizations_selected_option[:heading]
  end

  def organizations_select_list
    @organizations_select_list ||= [
      {
        heading: "No policy",
        description: "Organizations choose whether to allow organization projects.",
        value: "no_policy",
        selected: organizations_value == "no_policy",
      },
      {
        heading: "Enabled",
        description: "Organizations always have organization projects enabled.",
        value: "enabled",
        selected: organizations_value == "enabled",
      },
      {
        heading: "Disabled",
        description: "Organizations never have organization projects enabled.",
        value: "disabled",
        selected: organizations_value == "disabled",
      },
    ]
  end

  def organizations_input_value
    organizations_selected_option[:value]
  end

  def organizations_selected_option
    organizations_select_list.find { |s| s[:selected] }
  end

  def organizations_value
    if !business.organization_projects_policy?
      "no_policy"
    elsif business.organization_projects_enabled?
      "enabled"
    else
      "disabled"
    end
  end

  def organization_projects_setting_organizations_business_path
    urls.enterprise_organizations_setting_path(business, "organization_projects")
  end

  def repositories_form_path
    urls.update_settings_repository_projects_enterprise_path(business)
  end

  def repositories_button_text
    repositories_selected_option[:heading]
  end

  def repositories_select_list
    @repositories_select_list ||= [
      {
        heading: "No policy",
        description: "Organizations choose whether to allow repository projects.",
        value: "no_policy",
        selected: repositories_value == "no_policy",
      },
      {
        heading: "Enabled",
        description: "Organizations always have repository projects enabled.",
        value: "enabled",
        selected: repositories_value == "enabled",
      },
      {
        heading: "Disabled",
        description: "Organizations never have repository projects enabled.",
        value: "disabled",
        selected: repositories_value == "disabled",
      },
    ]
  end

  def repositories_input_value
    repositories_selected_option[:value]
  end

  def repositories_selected_option
    repositories_select_list.find { |s| s[:selected] }
  end

  def repositories_value
    if !business.repository_projects_policy?
      "no_policy"
    elsif business.repository_projects_enabled?
      "enabled"
    else
      "disabled"
    end
  end

  def repository_projects_setting_organizations_business_path
    urls.enterprise_organizations_setting_path(business, "repository_projects")
  end

  # "Public" projects in Enterprise Managed User (EMU) enterprises are only visible "internal" to the enterprise.
  # EMU enterprises do not have publicly exposed resources such as projects and repositories.
  # Non-EMU enterprises can have public projects, so we show the "public" option for them.
  def public_project_visibility_text
    if business.enterprise_managed_user_enabled?
      "internal"
    else
      "public"
    end
  end

  def members_can_change_project_visibility_setting_organizations_business_path
    urls.enterprise_organizations_setting_path(business, "members_can_change_project_visibility")
  end

  def members_can_change_visibility_form_path
    urls.update_members_can_change_project_visibility_enterprise_path(business)
  end

  def members_can_change_visibility_button_text
    members_can_change_visibility_selected_option[:heading]
  end

  def members_can_change_visibility_select_list
    @members_can_change_visibility_select_list ||= [
      {
        heading: "No policy",
        description: "Organizations choose whether to allow project admin members to change project visibility.",
        value: "no_policy",
        selected: members_can_change_visibility_value == "no_policy",
      },
      {
        heading: "Enabled",
        description: "Organizations always allow project admin members to change project visibility.",
        value: "enabled",
        selected: members_can_change_visibility_value == "enabled",
      },
      {
        heading: "Disabled",
        description: "Organizations never allow project admin members to change project visibility.",
        value: "disabled",
        selected: members_can_change_visibility_value == "disabled",
      },
    ]
  end

  def members_can_change_visibility_input_value
    members_can_change_visibility_selected_option[:value]
  end

  def members_can_change_visibility_selected_option
    members_can_change_visibility_select_list.find { |s| s[:selected] }
  end

  def members_can_change_visibility_value
    if !business.members_can_change_project_visibility_policy?
      "no_policy"
    elsif business.members_can_change_project_visibility?
      "enabled"
    else
      "disabled"
    end
  end

  def organization_projects_setting_visibility_business_path
    urls.organization_projects_visibility_settings_enterprise_path(business)
  end
end
