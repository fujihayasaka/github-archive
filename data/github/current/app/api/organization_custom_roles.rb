# typed: true
# frozen_string_literal: true

class Api::OrganizationCustomRoles < Api::App
  include ReceiveSchemaWithOpenApi

  get "/organizations/:organization_id/custom_roles", operation_id: "orgs/list-custom-roles" do
    deliver_error! 404 if changeset_active?(:update_custom_repo_role_path)
    # currently don't have a info_url for this deprecation
    deprecated(
      deprecation_date: Time.new(2023, 3, 6),
      sunset_date: Time.new(2025, 3, 6),
      info_url: "",
      alternate_path_url: "/orgs/{org}/custom-repository-roles/{role_id}"
    )
    org = find_org!
    return custom_role_not_supported_error(org) unless org.custom_roles_supported?

    control_access :read_org_custom_repo_roles,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    list_custom_repo_roles(org)
  end

  get "/organizations/:organization_id/custom-repository-roles", operation_id: "orgs/list-custom-repo-roles" do
    org = find_org!
    return custom_role_not_supported_error(org) unless org.custom_roles_supported?

    control_access :read_org_custom_repo_roles,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    list_custom_repo_roles(org)
  end

  def list_custom_repo_roles(org)
    custom_roles = RepositoryRole.custom_roles_for_org(org)

    GitHub::PrefillAssociations.prefill_associations(custom_roles, [:owner, :base_role], available_records: [org])
    deliver :custom_roles_hash, {
      custom_roles: custom_roles,
      total_count: custom_roles.length,
    }
  end

  get "/organizations/:organization_id/custom_roles/:role_id", operation_id: "orgs/get-custom-role" do
    # currently don't have a info_url for this deprecation
    deprecated(
      deprecation_date: Time.new(2023, 3, 6),
      sunset_date: Time.new(2023, 9, 6),
      info_url: "",
      alternate_path_url: "/orgs/{org}/custom-repository-roles/{role_id}"
    )
    org = find_org!
    return custom_role_not_supported_error(org) unless org.custom_roles_supported?

    control_access :read_org_custom_repo_roles,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    get_custom_repo_role(org)
  end

  get "/organizations/:organization_id/custom-repository-roles/:role_id", operation_id: "orgs/get-custom-repo-role" do
    org = find_org!
    return custom_role_not_supported_error(org) unless org.custom_roles_supported?

    control_access :read_org_custom_repo_roles,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    get_custom_repo_role(org)
  end

  def get_custom_repo_role(org)

    role = find_role!(org: org)

    deliver :custom_role_hash, role, status: 200
  end

  post "/organizations/:organization_id/custom_roles", operation_id: "orgs/create-custom-role" do
    # currently don't have a info_url for this deprecation
    deprecated(
      deprecation_date: Time.new(2023, 3, 6),
      sunset_date: Time.new(2023, 9, 6),
      info_url: "",
      alternate_path_url: "/orgs/{org}/custom-repository-roles/{role_id}"
    )
    org = find_org!
    return custom_role_not_supported_error(org) unless org.custom_roles_supported?

    control_access :modify_org_custom_repo_role,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    create_custom_repo_role(org)
  end

  post "/organizations/:organization_id/custom-repository-roles", operation_id: "orgs/create-custom-repo-role" do
    org = find_org!
    return custom_role_not_supported_error(org) unless org.custom_roles_supported?

    control_access :modify_org_custom_repo_role,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    create_custom_repo_role(org)
  end

  def create_custom_repo_role(org)
    custom_role_data = receive_with_openapi
    base_role = Role.preset_by_name(custom_role_data["base_role"])

    if base_role.nil?
      return deliver_error 422,
        message: "Invalid base role: #{custom_role_data["base_role"]}",
        documentation_url: @documentation_url
    end

    custom_role = RepositoryRole.new(
      owner_id: org.id,
      owner_type: "Organization",
      name: custom_role_data["name"],
      description: custom_role_data["description"],
      base_role_id: base_role.id
    )

    unless custom_role.valid?
      return deliver_error 422,
        message: custom_role.errors.full_messages.join(". "),
        documentation_url: @documentation_url
    end

    input_fgps = custom_role_data["permissions"].map(&:to_sym)
    valid_fgps, invalid_fgps = validate_fgp_input(input_fgps: input_fgps, org: org)
    unless invalid_fgps.empty?
      return deliver_error 422,
        message: invalid_permissions_message(invalid_fgps),
        documentation_url: @documentation_url
    end

    Permissions::CustomRoles.create!(custom_role, fgps: valid_fgps)
    deliver :custom_role_hash, custom_role, status: 201
  end

  delete "/organizations/:organization_id/custom_roles/:role_id", operation_id: "orgs/delete-custom-role" do
    # currently don't have a info_url for this deprecation
    deprecated(
      deprecation_date: Time.new(2023, 3, 6),
      sunset_date: Time.new(2023, 9, 6),
      info_url: "",
      alternate_path_url: "/orgs/{org}/custom-repository-roles/{role_id}"
    )
    org = find_org!
    return custom_role_not_supported_error(org) unless org.custom_roles_supported?

    control_access :modify_org_custom_repo_role,
      resource: org,
      organization: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    delete_custom_repo_role(org)
  end

  delete "/organizations/:organization_id/custom-repository-roles/:role_id", operation_id: "orgs/delete-custom-repo-role" do
    org = find_org!
    return custom_role_not_supported_error(org) unless org.custom_roles_supported?

    control_access :modify_org_custom_repo_role,
      resource: org,
      organization: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    delete_custom_repo_role(org)
  end

  def delete_custom_repo_role(org)

    role = find_role!(org: org)

    begin
      Permissions::CustomRoles.destroy!(role, current_user)
    rescue ActiveRecord::RecordNotFound
      return deliver_error 404
    rescue ActiveRecord::ActiveRecordError
      return deliver_error 500, message: "Role not deleted."
    end

    deliver_empty status: 204
  end

  patch "/organizations/:organization_id/custom_roles/:role_id", operation_id: "orgs/update-custom-role" do
    # currently don't have a info_url for this deprecation
    deprecated(
      deprecation_date: Time.new(2023, 3, 6),
      sunset_date: Time.new(2023, 9, 6),
      info_url: "",
      alternate_path_url: "/orgs/{org}/custom-repository-roles/{role_id}"
    )
    org = find_org!
    return custom_role_not_supported_error(org) unless org.custom_roles_supported?

    control_access :modify_org_custom_repo_role,
        resource: org,
        organization: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    update_custom_repo_role(org)
  end

  patch "/organizations/:organization_id/custom-repository-roles/:role_id", operation_id: "orgs/update-custom-repo-role" do
    org = find_org!
    return custom_role_not_supported_error(org) unless org.custom_roles_supported?

    control_access :modify_org_custom_repo_role,
        resource: org,
        organization: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    update_custom_repo_role(org)
  end

  def update_custom_repo_role(org)
    custom_role = find_role!(org: org)

    custom_role_data = receive_with_openapi

    name = custom_role_data.fetch("name", custom_role.name)
    description = custom_role_data.fetch("description", custom_role.description)
    base_role = Role.preset_by_name(custom_role_data["base_role"])
    base_role = custom_role.base_role if base_role.nil?

    custom_role_params = {
      name: name,
      description: description,
      base_role_id: base_role&.id
    }

    # Validate new FGPs if supplied, otherwise take from the existing role
    valid_fgps, invalid_fgps = if custom_role_data["permissions"]
      input_fgps = custom_role_data["permissions"].map(&:to_sym)
      validate_fgp_input(input_fgps: input_fgps, org: org)
    else
      [custom_role.custom_role_permissions.map(&:action), []]
    end

    unless invalid_fgps.empty?
      return deliver_error 422,
        message: invalid_permissions_message(invalid_fgps),
        documentation_url: @documentation_url
    end
    begin
      Permissions::CustomRoles.update!(custom_role, role_params: custom_role_params, fgps: valid_fgps, actor: current_user)

    rescue Role::CustomRoleError
      error_message = custom_role.errors.full_messages.to_sentence.presence || "Error updating custom role."

      return deliver_error 422,
        message: error_message,
        documentation_url: @documentation_url
    end

    custom_role.reload

    unless custom_role.valid?
      return deliver_error 422,
        message: custom_role.errors.full_messages.join(". "),
        documentation_url: @documentation_url
    end

    deliver :custom_role_hash, custom_role, status: 200
  end

  private

  def custom_role_not_supported_error(org) # rubocop:disable GitHub/ApiDeliverWrappersNamedDeliver
    deliver_error 404,
        message: "Feature not available for the #{org.login_for_api} organization.",
        documentation_url: @documentation_url
  end

  def find_role!(org:)
    record_or_404(find_custom_role_by_id_and_organization(org: org))
  end

  # Finds a role based on id and org owner and validates it is a custom role
  def find_custom_role_by_id_and_organization(org:)
    role_id = int_id_param!(key: :role_id)
    role = RepositoryRole.custom_roles_for_org(org).find_by(id: role_id)
    return nil unless role&.custom?
    role
  end

  # Validate an array of fine_grained_permission objects
  def validate_fgp_input(input_fgps:, org:)
    valid_fgps = input_fgps & RepoRoleFgps.custom_role_fgps(org)
    invalid_fgps = input_fgps - valid_fgps
    [valid_fgps, invalid_fgps]
  end

  def invalid_permissions_message(invalid_fgps)
    return "" if invalid_fgps.empty?
    return "Invalid permission: `#{invalid_fgps.first}`." if invalid_fgps.count == 1
    invalid_fgp_list = invalid_fgps.map { |fgp| %Q[`#{fgp}`] }.join(", ")
    "Invalid permissions: #{invalid_fgp_list}."
  end
end
