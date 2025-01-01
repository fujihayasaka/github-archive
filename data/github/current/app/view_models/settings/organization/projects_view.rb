# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

class Settings::Organization::ProjectsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization

  def organization_projects_policy?
    organization.organization_projects_policy?
  end

  def organization_projects_enabled_text
    organization.organization_projects_enabled? ? "enabled" : "disabled"
  end

  def organization_projects_label_class
    "color-fg-muted" if organization_projects_policy?
  end

  def organization_projects_label_text
    return "Enable #{GitHub.projects_new_enabled? ? "Projects" : "Projects (classic)"} for the organization" unless organization_projects_policy?

    helpers.safe_join([
      helpers.octicon("shield-lock"),
      "Organization projects have been",
      helpers.link_to("#{organization_projects_enabled_text} by enterprise administrators", GitHub.business_accounts_help_url) + ".",
    ], " ")
  end

  def repository_projects_policy?
    organization.repository_projects_policy?
  end

  def repository_projects_enabled?
    organization.repository_projects_enabled?
  end

  def repository_projects_enabled_text
    organization.repository_projects_enabled? ? "enabled" : "disabled"
  end

  def repository_projects_label_class
    "color-fg-muted" if repository_projects_policy?
  end

  def repository_projects_label_text
    return "Allow members to enable Projects (classic) for all repositories" unless repository_projects_policy?

    helpers.safe_join([
      helpers.octicon("shield-lock"),
      "Repository projects have been",
      helpers.link_to("#{repository_projects_enabled_text} by enterprise administrators", GitHub.business_accounts_help_url) + ".",
    ], " ")
  end

  # "Public" projects in Enterprise Managed User (EMU) enterprises are only visible "internal" to the enterprise.
  # EMU enterprises do not have publicly exposed resources such as projects and repositories.
  # Standalone organizations or those within non-EMU enterprises can have public projects, so we show the "public" option for them.
  def public_project_visibility_text
    if organization.enterprise_managed_user_enabled?
      "internal to the enterprise"
    else
      "public"
    end
  end

  def disable_projects_section_save_button?
    organization_projects_policy? && organization.members_can_change_project_visibility_policy?
  end

  def members_can_change_project_visibility_text
    organization.members_can_change_project_visibility? ? "enabled" : "disabled"
  end

  def members_can_change_project_visibility_label_class
    "color-fg-muted" if organization.members_can_change_project_visibility_policy?
  end

  def members_can_change_project_visibility_label_text
    unless organization.members_can_change_project_visibility_policy?
      return "Allow members to change project visibilities for this organization"
    end

    helpers.safe_join(
      [
        helpers.octicon("shield-lock"),
        "Member privileges for changing project visibilities have been",
        helpers.link_to(
          "#{members_can_change_project_visibility_text} by enterprise administrators",
          GitHub.business_accounts_help_url
        ) + ".",
      ],
      " "
    )
  end
end
