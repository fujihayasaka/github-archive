# typed: true
# frozen_string_literal: true

class Api::CopilotSpacesCollaborators < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::Serializer

  # ========================================================================
  # User-owned space endpoints
  # ========================================================================

  # GET /user/:user_id/copilot-spaces/:space_number/collaborators
  get "/user/:user_id/copilot-spaces/:space_number/collaborators",
      operation_id: "copilot-spaces/list-collaborators-for-user",
      read_from_replicas: true do

    user = find_user!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(user)

    space = find_owner_space!(user, params[:space_number])

    control_access :list_user_copilot_space_collaborators,
      resource: space,
      challenge: true,
      allow_integrations: false, # Do not allow server-to-server
      # Do not support FGP for user owned spaces due to testing constraints
      # ref https://github.com/github/api-permissions/issues/294
      # ref https://github.com/github/ecosystem-apps/discussions/7725
      allow_user_via_granular_actor: false

    # Only return user collaborators (exclude teams) and exclude the owner's permission
    user_roles = UserRole.where(target_type: "CustomCopilot", target_id: space.id, actor_type: "User")
                         .where.not(actor_id: space.owner.id)
                         .includes(:role, :actor)

    deliver :copilot_spaces_collaborator_list_hash, { user_roles: user_roles }
  end

  # POST /user/:user_id/copilot-spaces/:space_number/collaborators
  post "/user/:user_id/copilot-spaces/:space_number/collaborators", read_from_replicas: true,
       operation_id: "copilot-spaces/add-collaborator-for-user" do

    user = find_user!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(user)

    space = find_owner_space!(user, params[:space_number])

    control_access :manage_user_copilot_space_collaborators,
      resource: space,
      challenge: true,
      allow_integrations: false, # Do not allow server-to-server
      # Do not support FGP for user owned spaces due to testing constraints
      # ref https://github.com/github/api-permissions/issues/294
      # ref https://github.com/github/ecosystem-apps/discussions/7725
      allow_user_via_granular_actor: false

    data = receive_with_openapi.symbolize_keys
    actor = find_actor!(data[:actor_type], data[:actor_identifier], space.owner)
    role = find_role!(data[:role_name])

    # Check if permission already exists
    existing = UserRole.find_by(actor: actor, target_type: "CustomCopilot", target_id: space.id)
    if existing
      return deliver_error 422, message: "User already has a permission for this space"
    end

    with_write do
      Permissions::Granters::RoleGranter.new(actor: actor, target: space, role: role).grant!
      user_role = UserRole.find_by!(actor: actor, target_type: "CustomCopilot", target_id: space.id, role: role)
      deliver :copilot_space_collaborator_hash, user_role, status: 201
    end
  end

  # PUT /user/:user_id/copilot-spaces/:space_number/collaborators/:actor_type/:actor_identifier
  put "/user/:user_id/copilot-spaces/:space_number/collaborators/:actor_type/:actor_identifier", read_from_replicas: true,
      operation_id: "copilot-spaces/update-collaborator-for-user" do

    user = find_user!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(user)

    space = find_owner_space!(user, params[:space_number])

    control_access :manage_user_copilot_space_collaborators,
      resource: space,
      challenge: true,
      allow_integrations: false, # Do not allow server-to-server
      # Do not support FGP for user owned spaces due to testing constraints
      # ref https://github.com/github/api-permissions/issues/294
      # ref https://github.com/github/ecosystem-apps/discussions/7725
      allow_user_via_granular_actor: false

    actor = find_actor!(params[:actor_type], params[:actor_identifier], space.owner)
    data = receive_with_openapi.symbolize_keys
    role = find_role!(data[:role_name])

    with_write do
      Permissions::Granters::RoleGranter.new(actor: actor, target: space).revoke_if_exists!
      Permissions::Granters::RoleGranter.new(actor: actor, target: space, role: role).grant_unless_exists!
      user_role = UserRole.find_by!(actor: actor, target_type: "CustomCopilot", target_id: space.id, role: role)
      deliver :copilot_space_collaborator_hash, user_role
    end
  end

  # DELETE /user/:user_id/copilot-spaces/:space_number/collaborators/:actor_type/:actor_identifier
  delete "/user/:user_id/copilot-spaces/:space_number/collaborators/:actor_type/:actor_identifier", read_from_replicas: true,
         operation_id: "copilot-spaces/remove-collaborator-for-user" do

    user = find_user!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(user)

    space = find_owner_space!(user, params[:space_number])

    control_access :manage_user_copilot_space_collaborators,
      resource: space,
      challenge: true,
      allow_integrations: false, # Do not allow server-to-server
      # Do not support FGP for user owned spaces due to testing constraints
      # ref https://github.com/github/api-permissions/issues/294
      # ref https://github.com/github/ecosystem-apps/discussions/7725
      allow_user_via_granular_actor: false

    actor = find_actor!(params[:actor_type], params[:actor_identifier], space.owner)

    with_write do
      Permissions::Granters::RoleGranter.new(actor: actor, target: space).revoke_if_exists!
      status 204
    end
  end

  # ========================================================================
  # Organization-owned space endpoints
  # ========================================================================

  # GET /organizations/:org_id/copilot-spaces/:space_number/collaborators
  get "/organizations/:org_id/copilot-spaces/:space_number/collaborators",
      operation_id: "copilot-spaces/list-collaborators-for-org",
      read_from_replicas: true do

    org = find_org!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(org)

    space = find_owner_space!(org, params[:space_number])

    control_access :list_organization_copilot_space_collaborators,
      resource: space,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # Return both user and team collaborators, exclude the owner
    user_roles = UserRole.where(target_type: "CustomCopilot", target_id: space.id)
                         .where.not(actor_id: space.owner.id, actor_type: "Organization")
                         .includes(:role, :actor)

    deliver :copilot_spaces_collaborator_list_hash, { user_roles: user_roles }
  end

  # POST /organizations/:org_id/copilot-spaces/:space_number/collaborators
  post "/organizations/:org_id/copilot-spaces/:space_number/collaborators", read_from_replicas: true,
       operation_id: "copilot-spaces/add-collaborator-for-org" do

    org = find_org!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(org)

    space = find_owner_space!(org, params[:space_number])

    control_access :manage_organization_copilot_space_collaborators,
      resource: space,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi.symbolize_keys
    actor = find_actor!(data[:actor_type], data[:actor_identifier], space.owner)
    role = find_role!(data[:role_name])

    # Check if permission already exists
    existing = UserRole.find_by(actor: actor, target_type: "CustomCopilot", target_id: space.id)
    if existing
      actor_type_singular = { "users" => "User", "teams" => "Team" }[data[:actor_type].to_s] || data[:actor_type].capitalize
      return deliver_error 422, message: "#{actor_type_singular} already has a permission for this space"
    end

    with_write do
      Permissions::Granters::RoleGranter.new(actor: actor, target: space, role: role).grant!
      user_role = UserRole.find_by!(actor: actor, target_type: "CustomCopilot", target_id: space.id, role: role)
      deliver :copilot_space_collaborator_hash, user_role, status: 201
    end
  end

  # PUT /organizations/:org_id/copilot-spaces/:space_number/collaborators/:actor_type/:actor_identifier
  put "/organizations/:org_id/copilot-spaces/:space_number/collaborators/:actor_type/:actor_identifier", read_from_replicas: true,
      operation_id: "copilot-spaces/update-collaborator-for-org" do

    org = find_org!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(org)

    space = find_owner_space!(org, params[:space_number])

    control_access :manage_organization_copilot_space_collaborators,
      resource: space,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    actor = find_actor!(params[:actor_type], params[:actor_identifier], space.owner)
    data = receive_with_openapi.symbolize_keys
    role = find_role!(data[:role_name])

    with_write do
      Permissions::Granters::RoleGranter.new(actor: actor, target: space).revoke_if_exists!
      Permissions::Granters::RoleGranter.new(actor: actor, target: space, role: role).grant_unless_exists!
      user_role = UserRole.find_by!(actor: actor, target_type: "CustomCopilot", target_id: space.id, role: role)
      deliver :copilot_space_collaborator_hash, user_role
    end
  end

  # DELETE /organizations/:org_id/copilot-spaces/:space_number/collaborators/:actor_type/:actor_identifier
  delete "/organizations/:org_id/copilot-spaces/:space_number/collaborators/:actor_type/:actor_identifier", read_from_replicas: true,
         operation_id: "copilot-spaces/remove-collaborator-for-org" do

    org = find_org!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(org)

    space = find_owner_space!(org, params[:space_number])

    control_access :manage_organization_copilot_space_collaborators,
      resource: space,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    actor = find_actor!(params[:actor_type], params[:actor_identifier], space.owner)

    with_write do
      Permissions::Granters::RoleGranter.new(actor: actor, target: space).revoke_if_exists!
      status 204
    end
  end

  private

  # ========================================================================
  # Shared helper methods
  # ========================================================================

  def copilot_spaces_api_enabled?(owning_resource)
    FeatureFlag.vexi.enabled?("copilot_spaces_api", owning_resource, default: false) ||
      FeatureFlag.vexi.enabled?("copilot_spaces_api", current_user, default: false)
  end

  def find_user!
    user_identifier = params[:user_id]

    # Support both numeric IDs and usernames
    user = if user_identifier =~ /\A\d+\z/
      User.find_by(id: user_identifier)
    else
      User.find_by_login(user_identifier)
    end

    raise ActiveRecord::RecordNotFound unless user

    user
  end

  def find_owner_space!(owner, space_number)
    space = CopilotSpace.where(owner: owner).find_by(number: space_number)
    deliver_error!(404) unless space
    space.current_user = current_user
    space.cap_filter = cap_filter if respond_to?(:cap_filter)
    space
  end

  def find_actor!(actor_type, actor_identifier, owner)
    case actor_type
    when "users"
      find_user_actor!(actor_identifier)
    when "teams"
      find_team_actor!(actor_identifier, owner)
    else
      deliver_error!(422, message: "Invalid actor_type. Must be 'users' or 'teams'")
    end
  end

  def find_user_actor!(identifier)
    # Support both numeric IDs and usernames
    user = if identifier.to_s =~ /\A\d+\z/
      User.find_by(id: identifier)
    else
      User.find_by_login(identifier)
    end

    deliver_error!(404, message: "User not found") unless user
    user
  end

  def find_team_actor!(identifier, owner)
    # Teams only supported for organization-owned spaces
    if owner.user?
      deliver_error!(422, message: "Team collaborators are not supported for user-owned Copilot Spaces")
    end

    # identifier can be team slug or numeric ID
    # Teams must belong to the owning organization
    team = if identifier.to_s =~ /\A\d+\z/
      Team.find_by(id: identifier, organization_id: owner.id)
    else
      Team.find_by(slug: identifier, organization_id: owner.id)
    end

    deliver_error!(404, message: "Team not found in this organization") unless team
    team
  end

  def find_role!(role_name)
    case role_name
    when "reader"
      Role.custom_copilot_reader_role
    when "writer"
      Role.custom_copilot_writer_role
    when "admin"
      Role.custom_copilot_admin_role
    else
      deliver_error!(422, message: "Invalid role_name. Must be 'reader', 'writer', or 'admin'")
    end
  end
end
