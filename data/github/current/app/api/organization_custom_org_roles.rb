# typed: true
# frozen_string_literal: true

class Api::OrganizationCustomOrgRoles < Api::App
  extend T::Sig
  include ReceiveSchemaWithOpenApi

  get "/organizations/:organization_id/organization-roles", operation_id: "orgs/list-org-roles" do
    org = find_org!

    control_access :read_org_custom_org_role,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    roles = OrganizationRole.custom_roles_for_org(org)

    system_roles = OrganizationRole.visible_preset_roles(org)
    roles += system_roles

    deliver :org_roles_hash, {
      org: org,
      roles: roles,
      total_count: roles.length,
    }
  end

  get "/organizations/:organization_id/organization-roles/:role_id", operation_id: "orgs/get-org-role" do
    org = find_org!

    control_access :read_org_custom_org_role,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    role = find_org_role!
    deliver :typed_org_role_hash, role, status: 200
  end

  post "/organizations/:organization_id/organization-roles", operation_id: "orgs/create-custom-organization-role" do
    org = find_org!

    enforce_plan_supported!(org)

    control_access :modify_org_custom_org_role,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

    custom_role_data = receive_with_openapi

    if custom_role_data["base_role"].present?
      base_role_name = custom_role_data["base_role"]

      # Validate the base role at the API level.
      if !OrganizationRole::VALID_BASE_ROLES.include?(base_role_name)
        return deliver_error 422,
          message: "The base_role field must be one of: #{OrganizationRole::VALID_BASE_ROLES.join(", ")}. Please omit this field.",
          documentation_url: @documentation_url
      end

      base_role = RepositoryRole.system_repo_roles.find_by(name: base_role_name)
    end

    custom_role = OrganizationRole.new(
      owner_id: org.id,
      owner_type: "Organization",
      name: custom_role_data["name"],
      description: custom_role_data["description"],
      base_role: base_role,
    )

    unless custom_role.valid?
      return deliver_error 422,
        message: custom_role.errors.full_messages.join(". "),
        documentation_url: @documentation_url
    end

    input_fgps = custom_role_data["permissions"].map(&:to_sym)

    valid_fgps, invalid_fgps, invalid_repo_fgps = validate_org_fgp_input_new(input_fgps: input_fgps, org: org, base_role: base_role)
    if invalid_fgps.present? || invalid_repo_fgps.present?
      return deliver_error 422,
        message: invalid_permissions_message_new(invalid_fgps, invalid_repo_fgps),
        documentation_url: @documentation_url
    end
    Permissions::CustomRoles.create!(custom_role, fgps: valid_fgps)
    deliver :org_role_hash, custom_role, status: 201
  end

  patch "/organizations/:organization_id/organization-roles/:role_id", operation_id: "orgs/patch-custom-organization-role" do
    org = find_org!
    custom_role = find_custom_org_role!

    enforce_plan_supported!(org)

    control_access :modify_org_custom_org_role,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

    custom_role_data = receive_with_openapi

    name = custom_role_data.fetch("name", custom_role.name)
    description = custom_role_data.fetch("description", custom_role.description)

    base_role = nil

    if !custom_role_data.key?("base_role")
      # If base_role not passed => reuse current base_role
      base_role = custom_role.base_role
    elsif custom_role_data["base_role"]&.strip.present?
      # If base_role is present and not null/whitespace => means new base role to be used
      base_role_name = custom_role_data["base_role"].strip

      if base_role_name == "none"
        base_role = nil
      else
        # Validate the base role at the API level.
        unless OrganizationRole::VALID_BASE_ROLES.include?(base_role_name)
          return deliver_error 422,
            message: "The base_role field must be one of: #{OrganizationRole::VALID_BASE_ROLES.join(", ")}. Please omit this field.",
            documentation_url: @documentation_url
        end

        base_role = RepositoryRole.system_repo_roles.find_by(name: base_role_name)
      end
    end

    custom_role_params = {
      name: name,
      description: description,
      base_role: base_role,
    }

    unless custom_role.valid?
      return deliver_error 422,
        message: custom_role.errors.full_messages.join(". "),
        documentation_url: @documentation_url
    end

    # If permissions are passed we use them, otherwise we use the existing permissions
    if custom_role_data["permissions"]
      input_fgps = custom_role_data["permissions"].map(&:to_sym)
    else
      input_fgps = custom_role.custom_role_permissions.map(&:action).map(&:to_sym)
    end

    valid_fgps, invalid_fgps, invalid_repo_fgps = validate_org_fgp_input_new(input_fgps: input_fgps, org: org, base_role: base_role)
    if invalid_fgps.present? || invalid_repo_fgps.present?
      return deliver_error 422,
        message: invalid_permissions_message_new(invalid_fgps, invalid_repo_fgps),
        documentation_url: @documentation_url
    end

    begin
      Permissions::CustomRoles.update!(custom_role, role_params: custom_role_params, fgps: valid_fgps, actor: current_user)
    rescue Role::CustomRoleError
      error_message = custom_role.errors.full_messages.to_sentence.presence || "Error updating custom role."
      return deliver_error 422, message: error_message
    rescue ActiveRecord::RecordNotFound
      return deliver_error 404
    rescue ActiveRecord::ActiveRecordError
      return deliver_error 500, message: "Role not updated."
    end

    deliver :org_role_hash, custom_role, status: 200
  end

  delete "/organizations/:organization_id/organization-roles/:role_id", operation_id: "orgs/delete-custom-organization-role" do
    org = find_org!

    enforce_plan_supported!(org)

    control_access :modify_org_custom_org_role,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

    custom_role = find_custom_org_role!

    begin
      Permissions::CustomRoles.destroy!(custom_role)
    rescue ActiveRecord::RecordNotFound
      return deliver_error 404
    rescue ActiveRecord::ActiveRecordError
      return deliver_error 500, message: "Role not deleted."
    end

    deliver_empty status: 204
  end

  private

  def enforce_plan_supported!(org)
    deliver_error! 422, message: "Feature not available for the #{org.login_for_api} organization." unless org.custom_roles_supported?
  end

  # Validate an array of fine_grained_permission objects
  sig { params(input_fgps: T::Array[Symbol], org: Organization).returns([T::Array[Symbol], T::Array[Symbol]]) }
  def validate_org_fgp_input_legacy(input_fgps:, org:)
    valid_fgps = input_fgps & OrgRoleFgps.custom_role_fgps(org)
    invalid_fgps = input_fgps - valid_fgps
    [valid_fgps, invalid_fgps]
  end

  # Validate an array of fine_grained_permission objects considering both OrgRoleFgps and RoleFgps permissions based on the presence of base role.
  # If the base role is valid, include RoleFgps permissions in the validation.
  sig { params(input_fgps: T::Array[Symbol], org: Organization, base_role: T::nilable(RepositoryRole)).returns([T::Array[Symbol], T::Array[Symbol], T::Array[Symbol]]) }
  def validate_org_fgp_input_new(input_fgps:, org:, base_role: nil)
    # Always retrieve valid permissions from OrgRoleFgps
    combined_valid_fgps = OrgRoleFgps.custom_role_fgps(org)
    role_fgps = RoleFgps.custom_role_fgps(org)

    # Include RoleFgps permissions if there's a valid base role
    if base_role.present? && OrganizationRole::VALID_BASE_ROLES.include?(base_role.name)
      combined_valid_fgps += role_fgps
    end

    # Ensure uniqueness after potentially adding RoleFgps permissions
    combined_valid_fgps.uniq!

    # Determine valid and invalid permissions based on the combined set
    valid_fgps = input_fgps & combined_valid_fgps
    invalid_fgps = input_fgps - valid_fgps
    invalid_repo_fgps = []

    # If the base role is not present we identify fgps that would be valid if the base role was present
    unless base_role.present?
      input_fgps.each do |fgp|
        if role_fgps.include?(fgp)
          invalid_repo_fgps << fgp
        end
      end
      invalid_fgps -= invalid_repo_fgps
    end

    [valid_fgps, invalid_fgps, invalid_repo_fgps]
  end

  def invalid_permissions_message(invalid_fgps)
    return "" if invalid_fgps.empty?
    return "Invalid permission: `#{invalid_fgps.first}`." if invalid_fgps.count == 1
    invalid_fgp_list = invalid_fgps.map { |fgp| %Q[`#{fgp}`] }.join(", ")
    "Invalid permissions: #{invalid_fgp_list}."
  end

  def invalid_permissions_message_new(invalid_fgps, invalid_repo_fgps)
    return "" if invalid_fgps.empty? && invalid_repo_fgps.empty?
    message = ""
    unless invalid_fgps.empty?
      if invalid_fgps.count == 1
        message += "Invalid permission: `#{invalid_fgps.first}`."
      else
        invalid_fgp_list = invalid_fgps.map { |fgp| %Q[`#{fgp}`] }.join(", ")
        message += "Invalid permissions: #{invalid_fgp_list}."
      end
    end

    unless invalid_repo_fgps.empty?
      invalid_repo_fgp_list = invalid_repo_fgps.map { |fgp| %Q[`#{fgp}`] }.join(", ")
      repo_message = "Repository level permissions are only valid when a base repository role is provided: #{invalid_repo_fgp_list} could not be included."
      message += " " unless message.empty?
      message += repo_message
    end

    message
  end
end
