# typed: true
# frozen_string_literal: true

class Api::OrganizationFineGrainedOrgPermissions < Api::App
  include ReceiveSchemaWithOpenApi

  get "/organizations/:organization_id/organization-fine-grained-permissions", operation_id: "orgs/list-organization-fine-grained-permissions" do
    org = find_org!

    enforce_plan_supported!(org)

    control_access :read_org_custom_org_role,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    fgps = OrgRoleFgps.custom_role_fgps(org)

    deliver :org_fine_grained_permissions_hash, { fgps: fgps }
  end

  private

  def enforce_plan_supported!(org)
    deliver_error! 422, message: "Feature not available for the #{org.login_for_api} organization." unless org.custom_roles_supported?
  end
end
