# typed: strict
# frozen_string_literal: true

class Repositories::AccessManagement::EnterpriseAccessRowComponent < ApplicationComponent
  sig { returns(T.any(BusinessTeam, User)) }
  attr_reader :actor

  sig { returns(EnterpriseRole) }
  attr_reader :role

  sig { returns(Organization) }
  attr_reader :organization

  sig { returns(T::Hash[Symbol, Primer::SystemArgumentsValue]) }
  attr_reader :system_arguments

  sig do
    params(
      actor: T.any(BusinessTeam, User),
      role: EnterpriseRole,
      organization: Organization,
      system_arguments: Primer::SystemArgumentsValue,
    ).void
  end
  def initialize(actor:, role:, organization:, **system_arguments)
    @actor = actor
    @role = role
    @organization = organization
    @system_arguments = system_arguments
  end

  private

  sig { returns(T::Hash[String, T::Array[String]]) }
  def role_permissions
    return {} if delegate_organization_role.nil?

    RepoFgpMetadata.for_role(delegate_organization_role)
  end

  sig { returns(T.nilable(OrganizationRole)) }
  memoize def delegate_organization_role
    role.delegate_organization_role
  end

  sig { returns(T.nilable(Role)) }
  memoize def base_repo_role
    delegate_organization_role&.base_role
  end

  sig { returns(String) }
  def actor_profile_path
    case @actor
    when BusinessTeam
      UrlHelpers.team_path(team_slug: @actor.slug, org: @organization)
    when User
      user_path(@actor)
    else
      T.absurd(@actor)
    end
  end

  sig { returns(String) }
  def description
    case @actor
    when BusinessTeam
      "@#{@actor.slug} • #{pluralize(@actor.members_count, 'member')}"
    when User
      @actor.display_login
    else
      T.absurd(@actor)
    end
  end

  sig { returns(T::Boolean) }
  def show_role_in_preview?
    # True if the role is ESM
    role == EnterpriseRole.enterprise_security_manager_role
  end
end
