# typed: true
# frozen_string_literal: true

class Businesses::Settings::MemberPrivilegesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include ApplicationHelper
  include EnterpriseManagedUsersHelper

  attr_reader :business, :params

  def initialize(**args)
    super(args)
    @business = args[:business]
  end

  # "Base permissions" setting helpers

  def default_repository_permissions_change_form_path
    urls.update_default_repository_permission_enterprise_path(business)
  end

  def default_repository_permissions_select_list
    return @select_list if defined? @select_list

    none_description = if business.enterprise_managed_user_enabled?
      "Organization members will only be able to clone and pull internal repositories. Guest collaborators will not be able to access any repositories."
    elsif GitHub.public_repositories_available?
      "Organization members will only be able to clone and pull public and internal repositories."
    else
      "Organization members will not be able to clone and pull repositories."
    end
    @select_list = [
      {
        heading: "No policy",
        description: "Organizations choose base repository permissions for their members.",
        value: "no_policy",
        selected: default_repository_permissions_value == "no_policy",
      },
      {
        heading: Configurable::DefaultRepositoryPermission.human_friendly_value("none"),
        description: none_description,
        value: "none",
        selected: default_repository_permissions_value == "none",
      },
      {
        heading: Configurable::DefaultRepositoryPermission.human_friendly_value("read"),
        description: "Organization members will be able to clone and pull all organization repositories.",
        value: "read",
        selected: default_repository_permissions_value == "read",
      },
      {
        heading: Configurable::DefaultRepositoryPermission.human_friendly_value("write"),
        description: "Organization members will be able to clone, pull, and push all organization repositories.",
        value: "write",
        selected: default_repository_permissions_value == "write",
      },
      {
        heading: Configurable::DefaultRepositoryPermission.human_friendly_value("admin"),
        description: "Organization members will be able to clone, pull, push, and add new collaborators to all organization repositories.",
        value: "admin",
        selected: default_repository_permissions_value == "admin",
      },
    ]
  end

  def default_repository_permissions_value
    if !business.default_repository_permission_policy?
      return "no_policy"
    end

    case business.default_repository_permission
    when :admin
      "admin"
    when :write
      "write"
    when :read
      "read"
    when :none
      "none"
    end
  end

  def default_repository_permissions_button_text
    default_repository_permissions_selected_option[:heading]
  end

  def default_repository_permissions_selected_option
    default_repository_permissions_select_list.find { |s| s[:selected] }
  end

  def updating_default_repository_permissions?
    business.updating_default_repository_permission?
  end

  def default_repository_permission_setting_organizations_business_path
    urls.enterprise_organizations_setting_path(business, "default_repository_permission")
  end

  # "Repository visibility change" setting helpers

  def repo_visibility_change_form_path
    urls.update_members_can_change_repo_visibility_enterprise_path(business)
  end

  def repo_visibility_change_select_list
    @repo_visibility_change_select_list ||= [
      {
        heading: "No policy",
        description: "Organizations choose whether to allow members with admin permissions to change repository visibilities.",
        value: "no_policy",
        selected: repo_visibility_change_value == "no_policy",
      },
      {
        heading: "Enabled",
        description: "Organizations always allow members with admin permissions to change repository visibilities.",
        value: "enabled",
        selected: repo_visibility_change_value == "enabled",
      },
      {
        heading: "Disabled",
        description: "Organizations never allow members with admin permissions to change repository visibilities.",
        value: "disabled",
        selected: repo_visibility_change_value == "disabled",
      },
    ]
  end

  def repo_visibility_change_value
    if !business.members_can_change_repo_visibility_policy?
      "no_policy"
    elsif business.members_can_change_repo_visibility?
      "enabled"
    else
      "disabled"
    end
  end

  def repo_visibility_change_button_text
    repo_visibility_change_selected_option[:heading]
  end

  def repo_visibility_change_input_value
    repo_visibility_change_selected_option[:value]
  end

  def repo_visibility_change_selected_option
    repo_visibility_change_select_list.find { |s| s[:selected] }
  end

  def members_can_change_repository_visibility_setting_organizations_business_path
    urls.enterprise_organizations_setting_path(business, "members_can_change_repository_visibility")
  end

  # "Repository forking" setting helpers

  def allow_private_repository_forking_form_path
    urls.update_allow_private_repository_forking_enterprise_path(business)
  end

  def should_display_private_forking_policy_list?
    # only display the enhanced fork policy option list if the feature is enabled, and there is an allow private repository forking policy being enforced.
    business.allow_private_repository_forking_policy? && business.allow_private_repository_forking?
  end

  def allow_private_repository_forking_policy_list
    @allow_private_repository_forking_policy_list ||= [
      {
        title: "Organizations within this enterprise",
        description: "Members can fork a repository to an organization within this enterprise.",
        value: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS,
        selected: allow_private_repository_forking_policy_value == Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS,
        disabled: false,
      },
      {
        title: "Within the same organization",
        description: "Members can fork a repository only within the same organization (intra-org).",
        value: Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION,
        selected: allow_private_repository_forking_policy_value == Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION,
        disabled: false,
      },
      {
        title: "User accounts and within the same organization",
        description: if business.enterprise_managed_user_enabled?
                       "Members can fork a repository to their enterprise-managed user account or within the same organization."
                     else
                       "Members can fork a repository to their user account or within the same organization."
                     end,
        value: Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION_USER_ACCOUNTS,
        selected: allow_private_repository_forking_policy_value == Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION_USER_ACCOUNTS,
        disabled: restrict_repository_create_in_personal_namespace_enabled?,
      },
      {
        title: "User accounts and organizations within this enterprise",
        description: if business.enterprise_managed_user_enabled?
                       "Members can fork a repository to their enterprise-managed user account or an organization inside this enterprise."
                     else
                       "Members can fork a repository to their user account or an organization within this enterprise."
                     end,
        value: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS,
        selected: allow_private_repository_forking_policy_value == Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS,
        disabled: restrict_repository_create_in_personal_namespace_enabled?,
      },
      {
        title: "User accounts",
        description: if business.enterprise_managed_user_enabled?
                       "Members can fork a repository to their enterprise-managed user account."
                     else
                       "Members can fork a repository to their user account."
                     end,
        value: Configurable::AllowPrivateRepositoryForking::USER_ACCOUNTS,
        selected: allow_private_repository_forking_policy_value == Configurable::AllowPrivateRepositoryForking::USER_ACCOUNTS,
        disabled: restrict_repository_create_in_personal_namespace_enabled?,
      },
      {
        title: "Everywhere",
        description: "Members can fork a repository to their user account or an organization, either inside or outside of this enterprise.",
        value: Configurable::AllowPrivateRepositoryForking::EVERYWHERE,
        selected: allow_private_repository_forking_policy_value == Configurable::AllowPrivateRepositoryForking::EVERYWHERE || allow_private_repository_forking_policy_value == Configurable::AllowPrivateRepositoryForking::LEGACY_ENABLED,
        disabled: restrict_repository_create_in_personal_namespace_enabled?,
      }
    ]
  end

  def show_options_unavailable_message?
    allow_private_repository_forking_policy_list.map { |s| s[:disabled] }.include? true
  end

  def allow_private_repository_forking_select_list
    @allow_private_repository_forking_select_list ||= [
      {
        heading: "No policy",
        description: "Organizations choose whether to allow private and internal repositories to be forked.",
        value: "no_policy",
        selected: allow_private_repository_forking_value == "no_policy",
      },
      {
        heading: "Enabled",
        description: "Organizations always allow private and internal repositories to be forked.",
        value: "enabled",
        selected: allow_private_repository_forking_value == "enabled",
      },
      {
        heading: "Disabled",
        description: "Organizations never allow private or internal repositories to be forked.",
        value: "disabled",
        selected: allow_private_repository_forking_value == "disabled",
      },
    ]
  end

  def allow_private_repository_forking_value
    if !business.allow_private_repository_forking_policy?
      "no_policy"
    elsif business.allow_private_repository_forking?
      "enabled"
    else
      "disabled"
    end
  end

  def allow_private_repository_forking_policy_value
    business.get_private_repository_forking_policy
  end

  def allow_private_repository_forking_button_text
    allow_private_repository_forking_selected_option[:heading]
  end

  def allow_private_repository_forking_input_value
    allow_private_repository_forking_selected_option[:value]
  end

  def allow_private_repository_forking_selected_option
    allow_private_repository_forking_select_list.find { |s| s[:selected] }
  end

  def allow_private_repository_forking_setting_organizations_business_path
    urls.enterprise_organizations_setting_path(business, "allow_private_repository_forking")
  end

  # Members can update protected branches setting helpers

  def members_can_update_protected_branches_select_list
    @update_branch_protection_select_list ||= [
      {
        heading: "No policy",
        description: "Organization administrators choose whether to allow updating protected branches settings.",
        value: "no_policy",
        selected: members_can_update_protected_branches_value == "no_policy",
      },
      {
        heading: "Enabled",
        description: "Members with admin permissions will be able to update protected branches.",
        value: "enabled",
        selected: members_can_update_protected_branches_value == "enabled",
      },
      {
        heading: "Disabled",
        description: "Only business owners can update protected branches.",
        value: "disabled",
        selected: members_can_update_protected_branches_value == "disabled",
      },
    ]
  end

  def members_can_update_protected_branches_value
    if !business.members_can_update_protected_branches_policy?
      "no_policy"
    elsif business.members_can_update_protected_branches?
      "enabled"
    else
      "disabled"
    end
  end

  def members_can_update_protected_branches_button_text
    members_can_update_protected_branches_selected_option[:heading]
  end

  def members_can_update_protected_branches_input_value
    members_can_update_protected_branches_selected_option[:value]
  end

  def members_can_update_protected_branches_selected_option
    members_can_update_protected_branches_select_list.find { |s| s[:selected] }
  end

  def members_can_update_protected_branches_form_path
    urls.settings_members_can_update_protected_branches_enterprise_path(business)
  end

  def members_can_update_protected_branches_setting_organizations_business_path
    urls.enterprise_organizations_setting_path(business, "members_can_update_protected_branches")
  end

  # Members Can Delete Issues setting helpers

  def members_can_delete_issues_select_list
    @delete_issues_select_list ||= [
      {
        heading: "No policy",
        description: "Organization administrators choose whether to allow issue deletes.",
        value: "no_policy",
        selected: members_can_delete_issues_value == "no_policy",
      },
      {
        heading: "Enabled",
        description: "Members with admin permissions will be able to delete issues.",
        value: "enabled",
        selected: members_can_delete_issues_value == "enabled",
      },
      {
        heading: "Disabled",
        description: "Only organization owners can delete issues.",
        value: "disabled",
        selected: members_can_delete_issues_value == "disabled",
      },
    ]
  end

  def members_can_delete_issues_value
    if !business.members_can_delete_issues_policy?
      "no_policy"
    elsif business.members_can_delete_issues?
      "enabled"
    else
      "disabled"
    end
  end

  def members_can_delete_issues_button_text
    members_can_delete_issues_selected_option[:heading]
  end

  def members_can_delete_issues_input_value
    members_can_delete_issues_selected_option[:value]
  end

  def members_can_delete_issues_selected_option
    members_can_delete_issues_select_list.find { |s| s[:selected] }
  end

  def members_can_delete_issues_form_path
    urls.settings_members_can_delete_issues_enterprise_path(business)
  end

  def members_can_delete_issues_setting_organizations_business_path
    urls.enterprise_organizations_setting_path(business, "members_can_delete_issues")
  end

  # Members Can Delete or Transfer Repositories setting helpers

  def members_can_delete_repos_select_list
    @delete_repos_select_list ||= [
      {
        heading: "No policy",
        description: "Organization administrators choose whether to allow repository deletes and transfers.",
        value: "no_policy",
        selected: members_can_delete_repos_value == "no_policy",
      },
      {
        heading: "Enabled",
        description: "Members with admin permissions will be able to delete or transfer repositories.",
        value: "enabled",
        selected: members_can_delete_repos_value == "enabled",
      },
      {
        heading: "Disabled",
        description: "Only organization owners can delete or transfer repositories.",
        value: "disabled",
        selected: members_can_delete_repos_value == "disabled",
      },
    ]
  end

  def members_can_delete_repos_value
    if !business.members_can_delete_repositories_policy?
      "no_policy"
    elsif business.members_can_delete_repositories?
      "enabled"
    else
      "disabled"
    end
  end

  def members_can_delete_repos_button_text
    members_can_delete_repos_selected_option[:heading]
  end

  def members_can_delete_repos_input_value
    members_can_delete_repos_selected_option[:value]
  end

  def members_can_delete_repos_selected_option
    members_can_delete_repos_select_list.find { |s| s[:selected] }
  end

  def members_can_delete_repos_form_path
    urls.settings_members_can_delete_repositories_enterprise_path(business)
  end

  def members_can_delete_repositories_setting_organizations_business_path
    urls.enterprise_organizations_setting_path(business, "members_can_delete_repositories")
  end

  # Members Can Create Repositories setting helpers
  def members_can_create_repositories_no_policy_checked?
    !business.members_can_create_repositories_policy?
  end

  def members_can_create_repositories_disabled_checked?
    !members_can_create_repositories_no_policy_checked? && !any_repo_creation_enabled?
  end

  def members_can_create_repositories_allowed_checked?
    any_repo_creation_enabled?
  end

  def show_personal_repository_setting?
    current_user.is_enterprise_managed? || is_enterprise_to_restrict_for_personal_namespace?
  end

  def show_personal_repository_setting_copy
    business.enterprise_managed_user_enabled? ? "Members will not be able to create repositories in their enterprise-managed user account." : "Members will not be able to create repositories in their user accounts."
  end

  def show_personal_repository_list?
    show_personal_repository_setting? && business.show_user_namespace_repositories?
  end

  def restrict_repository_create_in_personal_namespace_path
    urls.restrict_repository_create_in_personal_namespace_enterprise_path(business)
  end

  def is_enterprise_to_restrict_for_personal_namespace?
    GitHub.single_business_environment?
  end

  def restrict_repository_create_in_personal_namespace_enabled?
    business.restrict_create_repository_in_personal_namespace_enabled?
  end

  private def any_repo_creation_enabled?
    all_disabled = !members_can_create_public_repos_checked? && !members_can_create_private_repos_checked?
    # This logic can move to the model once the backward-compatible GraphQL API goes away.
    all_disabled = all_disabled && !members_can_create_internal_repos_checked?
    !all_disabled
  end

  def show_public_repo_creation_option?
    GitHub.public_repositories_available? && !business.enterprise_managed_user_enabled?
  end

  def members_can_create_public_repos_checked?
    return nil unless business.members_can_create_repositories_policy?
    business.members_can_create_public_repositories?
  end

  def members_can_create_private_repos_checked?
    return nil unless business.members_can_create_repositories_policy?
    business.members_can_create_private_repositories?
  end

  def members_can_create_internal_repos_checked?
    return nil unless business.members_can_create_repositories_policy?
    business.members_can_create_internal_repositories?
  end

  def members_can_create_repos_form_path
    urls.settings_members_can_create_repositories_enterprise_path(business)
  end

  def repository_creation_setting_organizations_business_path
    urls.enterprise_organizations_setting_path(business, "repository_creation")
  end

  # Members Can invite outside collaborators setting helpers
  def outside_collaborators_setting_enabled?
    !business.enterprise_managed_user_enabled? || business.emu_repository_collaborators_policy_enabled?
  end

  def outside_collaborators_verbiage_view
    outside_collaborators_verbiage(business)
  end

  def members_can_invite_outside_collaborators_select_list
    @invite_outside_collaborators_select_list ||= [
      {
        heading: "No policy",
        description: "Organization administrators choose whether to allow members to #{invite_or_add_action_word.downcase} #{outside_collaborators_verbiage_view}.",
        value: "no_policy",
        selected: members_can_invite_outside_collaborators_value == "no_policy",
      },
      {
        heading: "Repository admins allowed",
        description: "Repository administrators can #{invite_or_add_action_word.downcase} #{outside_collaborators_verbiage_view}.",
        value: "repository_admins_allowed",
        selected: members_can_invite_outside_collaborators_value == "repository_admins_allowed",
      },
      {
        heading: "Organization owners only",
        description: "Only organization owners can #{invite_or_add_action_word.downcase} #{outside_collaborators_verbiage_view}.",
        value: "organization_admins_only",
        selected: members_can_invite_outside_collaborators_value == "organization_admins_only",
      },
      {
        heading: "Enterprise owners only",
        description: "Only enterprise owners can #{invite_or_add_action_word.downcase} #{outside_collaborators_verbiage_view}.",
        value: "enterprise_admins_only",
        selected: members_can_invite_outside_collaborators_value == "enterprise_admins_only",
      },
    ]
  end

  def members_can_invite_outside_collaborators_button_text
    members_can_invite_outside_collaborators_selected_option[:heading]
  end

  def members_can_invite_outside_collaborators_input_value
    members_can_invite_outside_collaborators_selected_option[:value]
  end

  def members_can_invite_outside_collaborators_selected_option
    members_can_invite_outside_collaborators_select_list.find { |s| s[:selected] }
  end

  def members_can_invite_outside_collaborators_form_path
    urls.settings_members_can_invite_outside_collaborators_enterprise_path(business)
  end

  def members_can_invite_collaborators_setting_organizations_business_path
    urls.enterprise_organizations_setting_path(business, "members_can_invite_collaborators")
  end

  # default branch rename helpers
  def business_has_custom_default_branch_setting?
    business.custom_default_new_repo_branch_name?
  end

  def current_default_new_repo_branch
    business.custom_default_new_repo_branch
  end

  def update_default_branch_name_path
    urls.update_default_branch_setting_enterprise_path(business)
  end

  def default_branch_name_currently_enforced?
    business.custom_default_new_repo_branch_enforced?
  end

  # deploy key policy helpers
  def update_deploy_key_policy_form_path
    urls.update_deploy_key_policy_enterprise_path(business)
  end

  private

  def members_can_invite_outside_collaborators_value
    if !business.members_can_invite_outside_collaborators_policy?
      "no_policy"
    elsif business.members_can_invite_outside_collaborators?
      "repository_admins_allowed" # disable_members_can_invite_outside_collaborators config = false
    elsif business.enterprise_admins_only_can_invite_outside_collaborators?
      "enterprise_admins_only"
    else
      "organization_admins_only" # disable_members_can_invite_outside_collaborators config = true
    end
  end
end
