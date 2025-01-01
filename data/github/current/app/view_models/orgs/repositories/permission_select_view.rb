# typed: true
# frozen_string_literal: true

class Orgs::Repositories::PermissionSelectView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include Repos::AccessManagementDependency

  attr_reader :repository, :selected_action, :submit_path, :team
  attr_reader :base_role, :is_org_member, :is_org_owner
  attr_reader :inherited_is_most_capable, :most_capable_permission_level, :ability

  ROLES = [
    {
      ability:      "read",
      permission:   "pull",
      description:  "Can read and clone this repository. Can also open and comment on issues and pull requests.",
    },
    {
      ability:      "triage",
      permission:   "triage",
      is_fgp:       true,
      description:  "Can read and clone this repository. Can also manage issues and pull requests.",
    },
    {
      ability:      "write",
      permission:   "push",
      description:  "Can read, clone, and push to this repository. Can also manage issues and pull requests.",
    },
    {
      ability:      "maintain",
      permission:   "maintain",
      is_fgp:       true,
      description:  "Can read, clone, and push to this repository. They can also manage issues, pull requests, and some repository settings.",
    },
    {
      ability:      "admin",
      permission:   "admin",
      description:  "Can read, clone, and push to this repository. Can also manage issues, pull requests, and repository settings, including adding collaborators.",
    },
  ]

  def selected_action?(action)
    selected_action == action
  end

  # Public: the title version of the selected action.
  # We capitalize system roles for readibility, but we leave custom roles as-is.
  #
  # Returns a String.
  def selected_action_name
    if Role::RESERVED_NAMES.include?(selected_action)
      selected_action.capitalize
    else
      selected_action
    end
  end

  # Public: Should we show FGP options as available permissions?
  #
  # Returns a Boolean.
  def fgp_available?
    return false if user_forked_repo?

    repository.plan_supports?(:fine_grained_permissions)
  end

  def org_owner?
    !!is_org_owner
  end

  def org_admin?
    return false if is_user_fork_of_private_org_repo?
    repository.organization.adminable_by?(current_user)
  end

  # Public: we show a warning in the individual role update dropdown if:
  # - the user is an org owner
  # - the user is an org member and the base role is above :read
  def show_base_role_warning?
    return true if org_owner?
    org_member? && !(base_role == :none || base_role == :read)
  end

  # Public: list of roles the member can be assigned.
  #
  # Returns an Array of Hashes
  def visible_roles
    roles = []

    ROLES.each do |role|
      roles.push(role) if show_role?(ability: role[:ability], is_fgp: role[:is_fgp])
    end
    roles
  end

  def disable_role?(role)
    team && repository.access_group_setting&.deny_role_change?(team&.id, role)
  end

  # Public: Sentence of roles below the org default permission.
  # Recall default permissions can only be :none, :read, :write, :admin.
  # An empty String is returned if no roles are below the org default.
  #
  # Returns a String
  def ignored_roles
    ignored = ROLES.select do |role|
      Ability::ACTION_RANKING[base_role] > Ability::ACTION_RANKING[role[:ability].to_sym]
    end.map { |role| role[:ability].titlecase }

    if repository.organization.custom_roles_supported?
      ignored += ignored_custom_roles.map(&:name)
    end

    return "" if ignored.blank?
    "#{ignored.to_sentence} are unavailable."
  end

  def show_custom_roles?
    repository.organization.custom_roles_supported? && org_custom_repo_roles.any?
  end

  def org_custom_repo_roles
    return unless repository.organization.custom_roles_supported?
    repository.organization.custom_repo_roles
  end

  def visible_custom_roles
    org_custom_repo_roles.select { |role| show_role?(ability: role.base_role.name, is_fgp: false) }
  end

  def ignored_custom_roles
    org_custom_repo_roles.select { |role| !show_role?(ability: role.base_role.name, is_fgp: false) }
  end

  def can_manage_roles?
    return false if is_user_fork_of_private_org_repo?
    repository.organization.custom_roles_supported? && repository.organization.adminable_by?(current_user)
  end

  def show_role_details?
    return false if is_user_fork_of_private_org_repo?
    repository.organization.custom_roles_supported? && repository.adminable_by?(current_user)
  end

  def role_label(role)
    label = role.is_a?(Hash) ? role[:ability].capitalize : role.name

    "#{label}#{inherited_text(role)}"
  end

  def permission_disabled?(role)
    return false unless most_capable_permission_level
    return false unless inherited_permission_level

    keys = Ability::ACTION_RANKING.keys
    role_name = role[:ability]&.to_sym
    index = keys.index(role[:ability]&.to_sym)
    role_name = keys[index + 1] if index && index < keys.size - 1
    helpers.permissions_option_disabled?(most_capable_permission_level, role_name) && helpers.permissions_option_disabled?(inherited_permission_level, role_name)
  end

  def custom_role_disabled?(role)
    return false unless most_capable_permission_level
    return false unless inherited_permission_level

    most_capable_permission_level > role.action_rank && inherited_permission_level > role.action_rank
  end

  private

  # Private: Does the repository belong to a user who has forked a private org-owned repo?
  #
  # Returns a Boolean.
  def user_forked_repo?
    repository.fork? && !repository.owner.organization? && repository.parent.in_organization?
  end

  # Private: wether to show the role for the member
  # There are 2 factors that weight in: if FGP is availabe and the org base role
  # Note that org owner roles can only be modified from /orgs/people
  #
  # Returns a Boolean
  def show_role?(ability:, is_fgp:)
    return if org_owner? && ability != "admin"

    if !is_fgp || (is_fgp && fgp_available?)
      !org_member? || above_or_equal_to_base_role?(ability.to_sym)
    end
  end

  def above_or_equal_to_base_role?(role)
    Ability::ACTION_RANKING[role] >= Ability::ACTION_RANKING.fetch(base_role, 0)
  end

  def org_member?
    !!is_org_member
  end

  def inherited_text(role)
    return if ability.blank?
    return unless inherited_is_most_capable
    return if role[:ability] && selected_action != role[:ability]
    return if role.is_a?(Role) && role.name != selected_action

    " (inherited from #{ability[:parent_name]})"
  end

  def inherited_permission_level
    ability[:parent_level]
  end
end
