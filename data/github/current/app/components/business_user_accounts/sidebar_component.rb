# typed: true
# frozen_string_literal: true

class BusinessUserAccounts::SidebarComponent < ApplicationComponent
  include BusinessesHelper
  include AvatarHelper

  attr_reader \
    :business,
    :user,
    :business_user_account,
    :organization_count,
    :team_count,
    :installation_count,
    :collab_repo_count

  def initialize(
    business:,
    user: nil,
    business_user_account: nil,
    organization_count: 0,
    team_count: 0,
    installation_count: 0,
    collab_repo_count: 0
  )
    @business = business
    @user = user
    @business_user_account = business_user_account
    @organization_count = organization_count
    @team_count = team_count
    @installation_count = installation_count
    @collab_repo_count = collab_repo_count
  end

  private

  memoize def role
    Business::Role.new(
      business,
      user,
      organization_count: organization_count || 0,
      installation_count: installation_count || 0,
      collab_repo_count: collab_repo_count || 0
    )
  end

  memoize def user_roles
    user_roles = []
    role.types.each do |type|
      if type == :outside_collaborator && business&.emu_repository_collaborators_enabled?
        user_roles << {
          name: "Repository collaborator",
          description: Business::Role.description_for_type(type, role),
        }
      else
        user_roles << {
          name: Business::Role.name_for_type(type),
          description: Business::Role.description_for_type(type, role),
        }
      end
    end

    user_roles
  end

  memoize def sso_status
    if business.external_provider.external_identities.linked_to(user).exists?
      "SSO identity linked"
    else
      "No SSO identity linked"
    end
  end

  # Should the metadata section should be shown in the sidebar?
  #
  # Returns Boolean.
  memoize def show_metadata_section?
    business_user_account.present? ||
    role.types.include?(:outside_collaborator) ||
    show_two_factor_status? ||
    show_sso_status?
  end

  # Should the SAML status for the person be shown? Only if SAML is
  # enabled for this Business
  #
  # Returns a Boolean
  memoize def show_sso_status?
    return false if user.nil?

    business.external_provider_enabled?
  end

  # Should the 2FA status for the person be shown?
  #
  # Returns true, only if:
  #
  # - This BusinessUserAccount has a dotcom User
  # - 2FA is enabled for the authentication system being used.
  # - The user is affiliated with the Business.
  # - The user is not part of a managed enterprise (EMU)
  #
  # Returns a Boolean
  memoize def show_two_factor_status?
    return false if user.nil?
    return false unless GitHub.auth.two_factor_authentication_enabled?
    return false if role.types.include?(:unaffiliated)
    return false if user.is_enterprise_managed?

    true
  end

  memoize def show_teams?
    return false if user.nil?
    GitHub.enterprise? || business.enterprise_managed_user_enabled?
  end

  # Get the display name for this account.
  #
  # Returns a String
  memoize def primary_name
    user_name = if user.nil?
      nil
    elsif user.profile_name.blank?
      user.display_login
    else
      user.profile_name
    end

    user_name || business_user_account&.display_login
  end

  def organizations_path
    return nil if business_user_account.nil? && user.nil?
    return organizations_enterprise_user_account_path(business_user_account) if user.nil?
    enterprise_person_organizations_enterprise_path(business, user)
  end

  def teams_path
    return nil if user.nil?
    enterprise_person_teams_enterprise_path(business, user)
  end

  def enterprise_installations_path
    return nil if business_user_account.nil?
    return enterprise_installations_enterprise_user_account_path(business_user_account) if user.nil?
    enterprise_person_enterprise_installations_enterprise_path(business, user)
  end
end
