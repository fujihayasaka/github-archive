# typed: false
# frozen_string_literal: true

module Orgs::RolesHelper
  def show_custom_roles?
    organization.custom_roles_supported? && custom_repo_roles_present?
  end

  def custom_repo_roles_present?
    custom_repo_roles.present?
  end

  def custom_repo_roles
    RepositoryRole.custom_roles_for_org(organization)
  end

  def system_roles
    fine_grained_permissions_supported? ? rank_system_roles(Role.system_repo_roles) : rank_system_roles(Role.primary_system_repo_roles)
  end

  def fine_grained_permissions_supported?
    organization.plan_supports?(:fine_grained_permissions)
  end

  def has_description?(role)
    role.description.present?
  end

  def organization_base_role(organization:)
    return nil if organization.nil?

    # Outside collaborators with repo admin privileges get access to the role details page too,
    # but since they're not a member of the parent org, we don't want to show them the default permission.
    return nil unless current_user_org_member?(organization)

    organization.default_repository_permission
  end

  def org_base_role?(role_name:, organization:)
    organization_base_role(organization: organization) == role_name
  end

  def icon_for_category(category)
    ::RepoFgpMetadata.icon_for_title(category)
  end

  def icon_for_role(role)
    case role.to_sym
    when :read
      "book"
    when :triage
      "checklist"
    when :write
      "pencil"
    when :maintain
      "tools"
    when :admin
      "eye"
    else
      "person"
    end
  end

  def system_role_description(role)
    case role.to_sym
    when :read
      "Read and clone repositories. Open and comment on issues and pull requests."
    when :triage
      "Read permissions plus manage issues and pull requests."
    when :write
      "Triage permissions plus read, clone and push to repositories."
    when :maintain
      "Write permissions plus manage issues, pull requests and some repository settings."
    when :admin
      "Full access to repositories including sensitive and destructive actions."
    end
  end

  def org_base_role
    organization.default_repository_permission
  end

  # Methods for Custom Org Roles

  def custom_org_roles
    organization.custom_org_roles
  end

  def org_roles_docs_url
    "#{GitHub.help_url}/organizations/managing-peoples-access-to-your-organization-with-roles/about-custom-organization-roles"
  end

  private

  def rank_system_roles(roles)
    roles.sort { |a, b| Ability::ACTION_RANKING[a.name.to_sym] <=> Ability::ACTION_RANKING[b.name.to_sym] }
  end

  def current_user_org_member?(organization)
    return @current_user_org_member if defined?(@current_user_org_member)

    @current_user_org_member = organization&.member?(current_user)
  end
end
