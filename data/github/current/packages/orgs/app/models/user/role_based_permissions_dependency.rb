# typed: true
# frozen_string_literal: true

module User::RoleBasedPermissionsDependency
  extend T::Helpers

  requires_ancestor { User }

  # Public: Returns the org roles assigned directly to the user.
  #
  # Returns an Array<OrganizationRole>.
  def org_roles_for(org)
    role_ids = UserRole.where(
      actor_type: "User",
      actor_id: self.id,
      target_type: "Organization",
      target_id: org.id
    ).select(:role_id).distinct

    Role.where(id: role_ids).includes(:permissions)
  end
end
