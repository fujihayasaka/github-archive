# typed: strict
# frozen_string_literal: true

module Business::RolesAndPermissionsDependency
  extend T::Helpers

  requires_ancestor { Business }

  # Public: This checks if the business supports custom organization roles
  sig { returns(T::Boolean) }
  def custom_organization_roles_supported?
    return false unless plan_supports?(:custom_roles)

    erp_feature_enabled?(:enterprise_custom_organization_roles)
  end

  sig { returns(T::Boolean) }
  def custom_enterprise_roles_supported?
    return false unless plan_supports?(:custom_roles)

    erp_feature_enabled?(:custom_enterprise_role_feature)
  end

  sig { returns(T::Boolean) }
  def enterprise_teams_org_roles_supported?
    erp_feature_enabled?(:enterprise_teams_org_roles)
  end

  sig { params(feature: Symbol).returns(T::Boolean) }
  def erp_feature_enabled?(feature)
    # feature flag in development
    return true if feature_enabled?(feature)

    # feature is staffshipped for this account
    return true if feature_enabled?("erp_staffship_#{feature}") && feature_enabled?(:erp_staffship)

    # feature is released to private preview
    feature_enabled?("erp_preview_#{feature}") && feature_enabled?(:erp_preview)
  end

  # Public: Grant a business team an organization role on all organizations.
  #
  # assignee - the business team granted the role
  # role     - the organization role to grant
  sig { params(assignee: BusinessTeam, role: OrganizationRole).returns(Permissions::Granters::RoleGrantResult) }
  def grant_org_role_on_all_orgs(assignee:, role:)
    T.bind(self, ::Business)

    if assignee.business_id != self.id
      reason = "Failed to grant role: #{role.name} - Invalid team for the enterprise"
      return Permissions::Granters::RoleGrantResult.failure!(reason:)
    end

    conditions = UserRoleCondition.new(target: UserRoleCondition::Target::AllOrgs)
    Permissions::Granters::RoleGranter.new(actor: assignee, target: self, role:, conditions:).grant_unless_exists!
  end

  # Public: Grant a business team an organization role on some organizations.
  #
  # assignee - the business team granted the role
  # role     - the organization role to grant
  # org_ids  - the organization IDs to grant the role on
  sig do
    params(
      assignee: BusinessTeam,
      role: OrganizationRole,
      org_ids: T::Array[Integer]
    ).returns(Permissions::Granters::RoleGrantResult)
  end
  def grant_org_role_on_some_orgs(assignee:, role:, org_ids:)
    T.bind(self, ::Business)

    if assignee.business_id != self.id
      reason = "Failed to grant role: #{role.name} - Invalid team for the enterprise"
      return Permissions::Granters::RoleGrantResult.failure!(reason:)
    end

    conditions = UserRoleCondition.new(target: UserRoleCondition::Target::SomeOrgs, target_ids: org_ids)
    Permissions::Granters::RoleGranter.new(actor: assignee, target: self, role:, conditions:).grant_unless_exists!
  end

  # Public: Revoke a business team an organization role.
  #
  # assignee - the business team granted the role
  # role     - the organization role to grant
  sig { params(assignee: BusinessTeam, role: OrganizationRole).returns(Permissions::Granters::RoleGrantResult) }
  def revoke_org_role(assignee:, role:)
    T.bind(self, ::Business)

    Permissions::Granters::RoleGranter.new(actor: assignee, target: self, role:).revoke_if_exists!
  end
end
