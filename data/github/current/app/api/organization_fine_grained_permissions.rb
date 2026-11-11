# typed: true
# frozen_string_literal: true

class Api::OrganizationFineGrainedPermissions < Api::App
  include ReceiveSchemaWithOpenApi

  get "/organizations/:organization_id/fine_grained_permissions", operation_id: "orgs/list-fine-grained-permissions" do
    # currently don't have a info_url for this deprecation
    deprecated(
      deprecation_date: Time.new(2023, 3, 6),
      sunset_date: Time.new(2023, 9, 6),
      info_url: "",
      alternate_path_url: "/orgs/{org}/custom-repository-roles/{role_id}"
    )
    org = find_org!
    unless org.custom_roles_supported?
      return deliver_error 404,
        message: "Feature not available for the #{org.login_for_api} organization.",
        documentation_url: @documentation_url
    end

    control_access :read_org_custom_repo_roles,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    list_fgps(org)
  end

  get "/organizations/:organization_id/repository-fine-grained-permissions", operation_id: "orgs/list-repo-fine-grained-permissions" do
    org = find_org!
    unless org.custom_roles_supported?
      return deliver_error 404,
        message: "Feature not available for the #{org.login_for_api} organization.",
        documentation_url: @documentation_url
    end

    control_access :read_org_custom_repo_roles,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    list_fgps(org)
  end

  def list_fgps(org)

    fgps = RepoRoleFgps.custom_role_fgps(org)

    deliver :fine_grained_permissions_hash, { fgps: fgps }
  end
end
