# typed: true
# frozen_string_literal: true

class Api::EnterpriseCustomEnterpriseRoles < Api::Enterprise::App
  get "/enterprises/:enterprise_id/enterprise-roles", operation_id: "enterprise-admin/list-enterprise-roles" do
    enterprise = find_enterprise!

    deliver_error! 404 unless enterprise.custom_enterprise_roles_supported?

    control_access :standard_authorization,
      resource: enterprise,
      permission: :read_enterprise_custom_enterprise_role,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    roles = EnterpriseRole.visible_roles(enterprise)
    GitHub::PrefillAssociations.prefill_associations(roles, [:custom_role_available_permissions, :owner])

    deliver :enterprise_roles_hash, { roles: roles, total_count: roles.length }, status: 200
  end

  get "/enterprises/:enterprise_id/enterprise-roles/:role_id", operation_id: "enterprise-admin/get-enterprise-role" do
    enterprise = find_enterprise!

    deliver_error! 404 unless enterprise.custom_enterprise_roles_supported?

    control_access :standard_authorization,
      resource: enterprise,
      permission: :read_enterprise_custom_enterprise_role,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    role = find_enterprise_role!(enterprise: enterprise, param_name: :role_id)
    deliver :typed_enterprise_role_hash, role, status: 200
  end
end
