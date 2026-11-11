# typed: true
# frozen_string_literal: true

class Stafftools::Codespaces::OrganizationSettingsComponent < ApplicationComponent
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def render?
    user.organization?
  end

  memoize def codespaces_enabled_users_count
    return 0 unless user.organization?

    ::User.where(id: selected_user_ids).count
  end

  memoize def codespaces_enabled_users
    return [] unless user.organization?

    ::User.where(id: selected_user_ids).limit(50)
  end

  memoize def integration_installations
    user.integration_installations.find_by(
      integration: Apps::Privileged.integration(:codespaces_production),
    )
  end

  memoize def current_org_trusted_repositories
    integration_installations&.repositories&.limit(50) || []
  end

  memoize def current_org_trusted_repositories_count
    integration_installations&.repositories&.count || 0
  end

  memoize def selected_user_ids
    UserRole.includes(:role).where(
      roles: { name: ::Codespaces::OrgPolicy::CODESPACE_ORG_CREATOR_ROLE },
      target_type: "Organization",
      target_id: user.id,
      actor_type: "User"
    ).pluck(:actor_id)
  end

  def access_setting
    return "" unless user.organization?
    user_limit = user.organization_codespaces_user_limit
    if user_limit == ::Configurable::OrganizationCodespacesUserLimit::ALL_USERS
      "All Members"
    elsif user_limit == ::Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS
      "All Members and outside collaborators"
    elsif user_limit == ::Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS
      "Selected Users"
    else
      "Disabled"
    end
  end

  def ownership_setting
    return "" unless user.organization?
    user_limit = user.organization_codespaces_ownership_setting&.capitalize
  end

  def access_and_security
    return "" unless user.organization?
    repository_access = user.codespace_trusted_repositories_access
    if repository_access == ::Configurable::CodespaceTrustedRepositories::ALL_REPOS
      "All Repositories"
    elsif repository_access == ::Configurable::CodespaceTrustedRepositories::SELECTED_REPOS
      "Selected Repositories"
    else
      "Disabled"
    end
  end
end
