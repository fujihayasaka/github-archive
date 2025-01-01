# typed: true
# frozen_string_literal: true

module Organization::OrganizationRolesDependency
  extend T::Helpers

  requires_ancestor { Organization }

  # Public: Grant a member or team an organization role for this organization.
  #
  # assignee - the user or team granted the role
  # role     - the organization role to grant
  sig { params(assignee: T.any(User, Team), role: OrganizationRole).returns(Permissions::Granters::RoleGrantResult) }
  def grant_org_role(assignee:, role:)
    T.bind(self, ::Organization)

    unless role.valid_org_role?(self)
      return Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to grant role: Role is invalid")
    end

    if assignee.is_a?(User) && !direct_member?(assignee)
      return Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to grant role: #{role.name} - #{assignee.display_login} is not a member of the organization")
    end

    if assignee.is_a?(Team) && assignee.organization_id != id
      return Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to grant role: #{role.name} - Invalid team for the organization")
    end

    Permissions::Granters::RoleGranter.new(actor: assignee, target: self, role: role).grant_unless_exists!
  end

  # Public: Revoke an organization role from a member or team for this organization.
  #
  # assignee - the user or team assigned the given role
  # role     - the organization role to revoke
  sig { params(assignee: T.any(User, Team), role: OrganizationRole).returns(Permissions::Granters::RoleGrantResult) }
  def revoke_org_role(assignee:, role:)
    T.bind(self, ::Organization)

    unless role.valid_org_role?(self)
      return Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to revoke role: Role is invalid")
    end

    if assignee.is_a?(User) && assignee.user? && !direct_member?(assignee)
      return Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to revoke role: #{role.name} - #{assignee.display_login} is not a member of the organization")
    end

    if assignee.is_a?(Team) && assignee.organization_id != id
      return Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to revoke role: #{role.name} - Team is not part of the organization")
    end

    if role == Role.security_manager_role
      unless SecurityCenter::FeatureFlagHelper.show_security_manager_in_org_role_assignment?(actor: self)
        return Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to revoke role: #{role.name} - Role cannot be revoked through this method")
      end

      if assignee.is_a?(Team) && assignee.enterprise_team_managed?
        enterprise_team = T.must(assignee.enterprise_team_organization_mapping&.enterprise_team)
        if SecurityProduct::EnterpriseSecurityManagerRole.granted?(enterprise_team)
          return Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to revoke role: #{role.name} - Role cannot be revoked from an enterprise security manager team")
        end
      end
    end

    Permissions::Granters::RoleGranter.new(actor: assignee, target: self, role: role).revoke_if_exists!
  end

  # Public: Revoke all organization roles from a member or team for this organization.
  #
  # assignee - the user or team assigned organization roles
  sig { params(assignee: T.any(User, Team)).returns(Permissions::Granters::RoleGrantResult) }
  def revoke_all_org_roles(assignee:)
    T.bind(self, ::Organization)

    if assignee.is_a?(::User) && assignee.user? && !direct_member?(assignee)
      return Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to revoke roles: #{assignee.display_login} is not a member of the organization")
    end

    # We cannot rely on RoleGranter's ability to revoke all user roles if the assignee is a security manager
    # because there are conditions where the security manager role should not be revoked.
    # The following logic is inspired by Permissions::Granters::RoleGranter#revoke_all_user_roles.
    if SecurityProduct::SecurityManagerRole.granted?(assignee, target: self)
      existing_roles = UserRole.where(actor: assignee, target_id: self.id, target_type: self.user_role_target_type)
      failed_role_names = []
      existing_roles.each do |user_role|
        role = user_role.role
        if role == Role.security_manager_role
          next unless SecurityCenter::FeatureFlagHelper.show_security_manager_in_org_role_assignment?(actor: self)

          # Do not revoke the organization security manager role if the assignee is an enterprise team with the enterprise security manager role
          if assignee.is_a?(Team) && assignee.enterprise_team_managed?
            enterprise_team = T.must(assignee.enterprise_team_organization_mapping&.enterprise_team)
            next if SecurityProduct::EnterpriseSecurityManagerRole.granted?(enterprise_team)
          end
        end

        try do
          Permissions::Granters::RoleGranter.new(actor: assignee, target: self, role:).revoke_if_exists!
        rescue Permissions::Granters::RoleGranter::GrantFailure => e
          failed_role_names << role.name
        end
      end

      if failed_role_names.any?
        result = Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to revoke roles: #{failed_role_names.join(", ")}")
        raise Permissions::Granters::RoleGranter::GrantFailure.new(result.reason)
      end

      return Permissions::Granters::RoleGrantResult.success!
    end

    # target type is an organization so this targets org custom roles
    Permissions::Granters::RoleGranter.new(actor: assignee, target: self).revoke_if_exists!
  end
end
