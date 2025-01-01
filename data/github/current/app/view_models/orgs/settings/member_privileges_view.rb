# typed: true
# frozen_string_literal: true

class Orgs::Settings::MemberPrivilegesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include EnterpriseManagedUsersHelper

  attr_reader :organization

  def default_repository_permissions_select_list
    return @select_list if defined?(@select_list)

    none_qualifier_for_environment = if GitHub.public_repositories_available?
      if organization.enterprise_managed_user_enabled?
        "Members will only be able to clone and pull internal repositories. Guest collaborators will not be able to access any repositories."
      elsif organization.business.present?
        "Members will only be able to clone and pull public and internal repositories."
      else
        "Members will only be able to clone and pull public repositories."
      end
    else
      "Members will not be able to clone and pull repositories."
    end


    none_description = "#{none_qualifier_for_environment} \
      To give a member additional access, you’ll need to add them to an \
      authorized team or make them a collaborator on individual repositories.".squish

    @select_list = [
      {
          heading: "No permission",
          description: none_description,
          value: "none",
          selected: organization.default_repository_permission == :none,
      },
      {
          heading: "Read",
          description: "Members will be able to clone and pull all repositories.",
          value: "read",
          selected: organization.default_repository_permission == :read,
      },
      {
          heading: "Write",
          description: "Members will be able to clone, pull, and push all repositories.",
          value: "write",
          selected: organization.default_repository_permission == :write,
      },
      {
          heading: "Admin",
          description: "Members will be able to clone, pull, push, and add new collaborators to all repositories.",
          value: "admin",
          selected: organization.default_repository_permission == :admin,
      },
    ]
  end

  def default_repository_permissions_button_text
    default_repository_permissions_selected_option[:heading]
  end

  def default_repository_permissions_input_value
    default_repository_permissions_selected_option[:value]
  end

  def default_repository_permissions_selected_option
    default_repository_permissions_select_list.find { |s| s[:selected] }
  end

  def default_repository_permissions_member_count
    organization.members_count
  end

  def default_repository_permissions_repository_count
    @repository_count ||= organization.repositories.count
  end

  def default_repository_permissions_need_confirmation?
    default_repository_permissions_repository_count > 0 && default_repository_permissions_member_count > 0
  end

  def members_can_change_repo_visibility_business_policy_set?
    organization.members_can_change_repo_visibility_policy?
  end

  # used to disable inputs in the UI. if a business policy is set then the org owner can't change it.
  def members_can_change_repo_visibility_disabled?
    members_can_change_repo_visibility_business_policy_set?
  end

  def members_can_change_repo_visibility_policy_action
    return nil unless members_can_change_repo_visibility_business_policy_set?

    organization.members_can_change_repo_visibility? ? "enabled" : "disabled"
  end

  def members_can_invite_outside_collaborators_policy_action
    organization.members_can_invite_outside_collaborators? ? "enabled" : "disabled"
  end

  def allow_forking_repo_label
    organization.supports_internal_repositories? ? "private and internal" : "private"
  end

  def allow_forking_repo_description
    if GitHub.public_repositories_available?
      organization.supports_internal_repositories? ? "private, internal, and public" : "private and public"
    else
      organization.supports_internal_repositories? ? "private and internal" : "private"
    end
  end

  # Whether the option cannot be set at the org level.
  # Unable to be set when the enterprise has disabled forking.
  def allow_private_repository_forking_disabled?
    return allow_private_repository_forking_disabled_by_enterprise? if organization.supports_enhanced_enterprise_forking_policies?

    organization&.business&.allow_private_repository_forking_policy?
  end

  # Should we show the expanded forking policy options for this org?
  def should_show_expanded_forking_policy_options?
    organization.supports_enhanced_enterprise_forking_policies?
  end

  #
  def allow_private_repository_forking_policy_options
    return @allow_private_repository_forking_policy_options if defined?(@allow_private_repository_forking_policy_options)

    # if the enterprise disabled forking, no options should be returned
    if allow_private_repository_forking_disabled_by_enterprise?
      @allow_private_repository_forking_policy_options = []
      return @allow_private_repository_forking_policy_options
    end

    # Load the forking policy options available to the org.
    available_options = organization.get_valid_policy_options_for_private_repository_forking_policy

    @allow_private_repository_forking_policy_options = []

    allow_private_repository_forking_policy_list.each do |_policy, option|
      option[:disabled] = available_options && !available_options.include?(option[:value]) && !option[:selected] && option[:value] != allow_private_repository_forking_inherited_policy_value
      @allow_private_repository_forking_policy_options << option
    end

    @allow_private_repository_forking_policy_options
  end

  # Whether the enterprise policy has disabled any forking policy options for the org.
  def any_forking_policies_disabled_by_enterprise_setting?
    return false unless organization.business

    allow_private_repository_forking_policy_options.any? { |option| option[:disabled] }
  end

  def allow_private_repository_forking_policy_value
    organization.get_private_repository_forking_policy || organization.business&.get_private_repository_forking_policy
  end

  def allow_private_repository_forking_inherited_policy_value
    organization.business&.get_private_repository_forking_policy
  end

  # Has the enterprise disabled forking?
  def allow_private_repository_forking_disabled_by_enterprise?
    return false unless organization.business

    organization.business.allow_private_repository_forking_policy? && !organization.business.allow_private_repository_forking?
  end

  def allow_private_repository_forking_policy_list
    @allow_private_repository_forking_policy_list ||= { Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS =>
      {
        title: "Organizations within this enterprise",
        description: "Members can fork a repository to an organization within #{organization.business&.name}.",
        value: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS,
        selected: allow_private_repository_forking_policy_value == Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS,
      },
      Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION =>
      {
        title: "Within the same organization",
        description: "Members can fork a repository only within the same organization (intra-org).",
        value: Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION,
        selected: allow_private_repository_forking_policy_value == Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION,
      },
      Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION_USER_ACCOUNTS =>
      {
        title: "User accounts and within the same organization",
        description: if organization.business&.enterprise_managed_user_enabled?
                       "Members can fork a repository to their enterprise-managed user account or within the same organization."
                     else
                       "Members can fork a repository to their user account or within the same organization."
                     end,
        value: Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION_USER_ACCOUNTS,
        selected: allow_private_repository_forking_policy_value == Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION_USER_ACCOUNTS,
      },
      Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS =>
      {
        title: "User accounts and organizations within this enterprise",
        description: if organization.business&.enterprise_managed_user_enabled?
                       "Members can fork a repository to their enterprise-managed user account or an organization inside #{organization.business&.name}."
                     else
                       "Members can fork a repository to their user account or an organization within #{organization.business&.name}."
                     end,
        value: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS,
        selected: allow_private_repository_forking_policy_value == Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS,
      },
      Configurable::AllowPrivateRepositoryForking::USER_ACCOUNTS =>
      {
        title: "User accounts",
        description: if organization.business&.enterprise_managed_user_enabled?
                       "Members can fork a repository to their enterprise-managed user account."
                     else
                       "Members can fork a repository to their user account."
                     end,
        value: Configurable::AllowPrivateRepositoryForking::USER_ACCOUNTS,
        selected: allow_private_repository_forking_policy_value == Configurable::AllowPrivateRepositoryForking::USER_ACCOUNTS,
      },
      Configurable::AllowPrivateRepositoryForking::EVERYWHERE =>
      {
        title: "Everywhere",
        description: "Members can fork a repository to their user account or an organization, either inside or outside of #{organization.business&.name}.",
        value: Configurable::AllowPrivateRepositoryForking::EVERYWHERE,
        selected: allow_private_repository_forking_policy_value == Configurable::AllowPrivateRepositoryForking::EVERYWHERE || allow_private_repository_forking_policy_value == Configurable::AllowPrivateRepositoryForking::LEGACY_ENABLED,
      }
    }
  end

  def show_discussion_creation_setting?
    GitHub.discussions_available_on_platform? && organization.repositories.any?
  end

  def can_delete_repos_form_path
    urls.organization_members_can_delete_repositories_path(organization)
  end

  def can_delete_issues_form_path
    urls.organization_members_can_delete_issues_path(organization)
  end

  def display_commenter_full_name_path
    urls.organization_display_commenter_full_name_path(organization)
  end

  def readers_can_create_discussions_path
    urls.organization_readers_can_create_discussions_path(organization)
  end

  def can_update_protected_branches_form_path
    urls.organization_members_can_update_protected_branches_path(organization)
  end

  def can_create_teams_form_path
    urls.organization_members_can_create_teams_path(organization)
  end

  def members_can_delete_repositories_action
    organization.members_can_delete_repositories? ? "enabled" : "disabled"
  end

  def members_can_delete_issues_action
    organization.members_can_delete_issues? ? "enabled" : "disabled"
  end

  def display_commenter_full_name_action
    organization.display_commenter_full_name_setting_enabled? ? "enabled" : "disabled"
  end

  def display_commenter_full_name_action_when_enforced?
    if organization.business.present?
      organization.business.display_commenter_full_name_enforced? # unselectable on org level if enforced by business policy
    else
      false
    end
  end

  def members_can_update_protected_branches_action
    organization.members_can_update_protected_branches? ? "enabled" : "disabled"
  end

  # Repo creation policy

  def members_can_create_repositories_policy_set?
    organization.members_can_create_repositories_policy?
  end

  def members_can_create_public_repos_disabled?
    members_can_create_repositories_policy_set? ||
      (!organization.can_restrict_only_public_repo_creation? && organization.members_can_create_private_repositories?)
  end

  def members_can_create_private_repos_disabled?
    members_can_create_repositories_policy_set?
  end

  def members_can_create_internal_repos_disabled?
    members_can_create_repositories_policy_set?
  end

  def show_internal_repo_creation_option?
    organization.supports_internal_repositories?
  end

  def private_only_policy_allowed?
    organization.can_restrict_only_public_repo_creation?
  end

  def repo_creation_privileges_doc_link
    helpers.link_to(
      "Why is this option disabled?",
       GitHub.help_url + "/articles/restricting-repository-creation-in-your-organization",
       {
        hidden: !members_can_create_public_repos_disabled? || members_can_create_repositories_policy_set?,
        class: "js-public-disabled-doc-link Link--inTextBlock",
       },
    )
  end

  # Repo deletion policy

  def members_can_delete_repositories_policy_set?
    organization.members_can_delete_repositories_policy?
  end

  def members_can_delete_issues_policy_set?
    organization.members_can_delete_issues_policy?
  end

  # Outside collaborators policy

  def repo_admins_can_invite_outside_collaborators_policy_set?
    organization.members_can_invite_outside_collaborators_policy?
  end

  def show_outside_collaborators?
    organization.enterprise_managed_user_enabled? ? organization.business&.emu_repository_collaborators_enabled? : organization.can_restrict_repo_invites?
  end

  # Protected branches policy

  def members_can_update_protected_branches_policy_set?
    organization.members_can_update_protected_branches_policy?
  end

  # Dependency insights

  def can_restrict_dependency_insights?
    organization.dependency_insights_enabled_for?(current_user)
  end

  def members_can_view_dependency_insights_set?
    organization.members_can_view_dependency_insights_policy?
  end

  def members_can_view_dependency_insights_policy_action
    organization.members_can_view_dependency_insights? ? "enabled" : "disabled"
  end

  # Custom roles

  def affected_custom_roles(action)
    custom_role_count = dependant_custom_roles_count(action)

    "#{custom_role_count} custom #{'role'.pluralize(custom_role_count)}"
  end

  def affected_members(action)
    member_count = dependant_custom_role_members_count(action)

    "#{member_count} #{'member'.pluralize(member_count)}"
  end

  def affected_repositories(action)
    repository_count = dependant_custom_role_repositories_count(action)

    "#{repository_count} #{'repository'.pluralize(repository_count)}"
  end

  # Pages access controls

  def plan_supports_pages_access_controls?
    organization.org_business_plus_plan?
  end

  def pages_access_controls_disabled_doc_link
    helpers.link_to(
      "Why is this option disabled?",
      "#{GitHub.help_url}/github/working-with-github-pages/changing-the-visibility-of-your-github-pages-site",
       {
        hidden: plan_supports_pages_access_controls?,
        class: "Link--inTextBlock"
       }
    )
  end

  def pages_access_controls_disabled_text_style
    if plan_supports_pages_access_controls?
      ""
    else
      "color-fg-muted"
    end
  end

  private

  def dependant_custom_roles_count(action)
    dependant_custom_roles(action).count
  end

  def dependant_custom_role_members_count(action)
    UserRole
    .select(:actor_id).distinct
    .where(actor_type: "User", actor_id: org_member_ids, target_type: "Repository", role_id: dependant_custom_roles(action)).count
  end

  def dependant_custom_role_repositories_count(action)
    UserRole
    .select(:target_id).distinct
    .where(actor_type: "User", actor_id: org_member_ids, target_type: "Repository", role_id: dependant_custom_roles(action)).count
  end

  def dependant_custom_roles(action)
    RepositoryRole.lower_custom_role_ids(action: action, org: organization)
  end

  def org_member_ids
    return @org_member_ids if defined?(@org_member_ids)
    @org_member_ids = organization.member_ids
  end

  # returns a hash with values for members_can_create_repos_select_list
  def members_can_create_repo_settings(val)
    {
      all: {
        heading: "Public and private repositories",
        description: "Members will be able to create public and private repositories.",
        value: "all",
      },
      private: {
        heading: "Private repositories",
        description: "Members will be able to create only private repositories.",
        value: "private",
      },
      none: {
        heading: "Disabled",
        description: "Members will not be able to create public or private repositories.",
        value: "none",
      },
    }[val]
  end
end
