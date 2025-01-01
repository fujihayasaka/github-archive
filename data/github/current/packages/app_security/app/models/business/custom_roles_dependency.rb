# typed: strict
# frozen_string_literal: true

module Business::CustomRolesDependency
  extend T::Helpers

  requires_ancestor { Business }

  sig { returns(T::Array[EnterpriseRole]) }
  def roles_assignable_to_target
    EnterpriseRole.visible_roles(T.cast(self, Business))
  end

  # Public: Grant a member or team an enterprise role for this business.
  #
  # assignee - the user or team granted the role
  # role     - the enterprise role to grant
  sig { params(assignee: T.any(User, BusinessTeam), role: EnterpriseRole).returns(Permissions::Granters::RoleGrantResult) }
  def grant_enterprise_role(assignee:, role:)
    T.bind(self, Business)

    Permissions::Granters::EnterpriseRoleGranter.grant_role(actor: assignee, target: self, role: role)
  end

  # Public: Revoke an enterprise role from a member or team for this business.
  #
  # assignee - the user or team to revoke the role from
  # role     - the enterprise role to revoke
  sig { params(assignee: T.any(User, BusinessTeam), role: EnterpriseRole).returns(Permissions::Granters::RoleGrantResult) }
  def revoke_enterprise_role(assignee:, role:)
    T.bind(self, Business)

    Permissions::Granters::EnterpriseRoleGranter.revoke_role(actor: assignee, target: self, role: role)
  end

  # Public: Revoke all enterprise roles from a member or team for this business.
  #
  # assignee - the user or team assigned enterprise roles
  sig { params(assignee: T.any(User, BusinessTeam)).returns(Permissions::Granters::RoleGrantResult) }
  def revoke_all_enterprise_roles(assignee:)
    T.bind(self, Business)

    failed_role_names = []
    enterprise_roles = EnterpriseRole
      .joins(:user_roles)
      .where(user_roles: { actor: assignee, target_id: self.id, target_type: self.user_role_target_type })

    enterprise_roles.each do |role|
      revoke_enterprise_role(assignee:, role:)
    rescue Permissions::Granters::RoleGranter::GrantFailure => e
      failed_role_names << role.name
    end

    if failed_role_names.any?
      return Permissions::Granters::RoleGrantResult.failure!(reason: "Failed to revoke roles: #{failed_role_names.join(", ")}")
    end

    Permissions::Granters::RoleGrantResult.success!
  end
end
