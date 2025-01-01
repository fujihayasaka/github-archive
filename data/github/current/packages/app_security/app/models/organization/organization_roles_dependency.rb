# typed: true
# frozen_string_literal: true

module Organization::OrganizationRolesDependency
  extend T::Helpers

  requires_ancestor { Organization }

  # Public: Grant a member of this organization an organization role.
  #
  # member - the user is granted the role
  # role   - the role organization role to grant
  def grant_org_role(assignee:, role:)
    unless role.valid_org_role?(self)
      return Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to grant role: Role is invalid")
    end
    unless role.is_a? OrganizationRole
      return Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to grant role: #{role.id} - Role needs to be an organization role")
    end
    if assignee.is_a?(User) && !direct_member?(assignee)
      return Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to grant role: #{role.name} - #{assignee.display_login} is not a member of the organization")
    end
    if assignee.is_a?(Team) && assignee.organization_id != id
      return Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to grant role: #{role.name} - Invalid team for the organization")
    end

    Permissions::Granters::RoleGranter.new(actor: assignee, target: self, role: role).grant_unless_exists!
  end

  # Public: Revoke a member of this organization an organization role.
  #
  # member - the user is granted the role
  # role   - the role organization role to grant
  def revoke_org_role(assignee:, role:)
    unless role.valid_org_role?(self)
      return Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to revoke role: Role is invalid")
    end
    unless role.is_a? OrganizationRole
      return Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to revoke role: #{role.id} - Role needs to be an organization role")
    end
    if assignee.try(:user?) && !direct_member?(assignee)
      return Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to revoke role: #{role.name} - #{assignee.display_login} is not a member of the organization")
    end
    if assignee.is_a?(Team) && assignee.organization_id != id
      return Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to revoke role: #{role.name} - Team is not part of the organization")
    end

    Permissions::Granters::RoleGranter.new(actor: assignee, target: self, role: role).revoke_if_exists!
  end

  # Public: Revoke all organization roles for a member of this organization.
  #
  # assignee - the user that is assigned roles
  def revoke_all_org_roles(assignee:)
    if assignee.try(:user?) && !direct_member?(assignee)
      return Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to revoke roles: #{assignee.display_login} is not a member of the organization")
    end

    # target type is an organization so this targets org custom roles
    Permissions::Granters::RoleGranter.new(actor: assignee, target: self).revoke_if_exists!
  end
end
