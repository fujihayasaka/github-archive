# typed: true
# frozen_string_literal: true

module Repository::EnterpriseManagedUserMethods
  include Repos::GitHubEnterpriseHelper

  # https://github.com/github/special-projects/issues/1057
  def creating_repo_in_personal_namespace_for_emu?(user)
    user.is_enterprise_managed?
  end

  def creating_repo_in_personal_namespace?(user, owner)
    user.id == owner.id
  end

  def creating_repo_in_personal_namespace_enterprise_setting_enabled?(user)
    restrict_create_repositories_in_personal_namespace?(user)
  end

  def creating_repo_in_personal_namespace_enterprise_setting_message(user)
    user.is_enterprise_managed? ? "Repository creation using enterprise-managed user account inside this enterprise is not allowed." : "Repository creation using user account inside this enterprise is not allowed."
  end

  def is_enterprise_to_restrict_for_personal_namespace?
    GitHub.single_business_environment?
  end

  def creation_blocked_for_repo_in_personal_namespace?(user, owner)
    (creating_repo_in_personal_namespace_for_emu?(user) || is_enterprise_to_restrict_for_personal_namespace?) &&
    creating_repo_in_personal_namespace_enterprise_setting_enabled?(user) &&
    creating_repo_in_personal_namespace?(user, owner)
  end
end
