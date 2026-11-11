# typed: true
# frozen_string_literal: true

class Api::CopilotSpaces < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::Serializer
  include CopilotSpaces::Pagination
  include CopilotSpaces::RoleMapping
  include CopilotSpaces::ApiAnalytics
  include CopilotSpaces::ResourceFiltering
  include CopilotSpaces::ApiRequestValidation
  include CopilotSpaces::RepoScopeAuthz

  INTERNAL_ERROR_ATTRIBUTES = %w[slug].freeze

  # GET /organizations/:organization_id/copilot-spaces
  get "/organizations/:organization_id/copilot-spaces",
      operation_id: "copilot-spaces/list-for-org",
      read_from_replicas: true do
    org = find_org!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(org)

    control_access :list_organization_copilot_spaces,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    per_page = parse_per_page(params)
    current_cursor = parse_pagination_cursor_or_error!(params, per_page)
    spaces_plus_one = find_org_spaces(org, current_cursor)

    track_spaces_api_event("list_spaces", nil, owner_type: "Organization")
    handle_paginated_list_response(spaces_plus_one, current_cursor, per_page)
  end

  # GET /organizations/:organization_id/copilot-spaces/:space_number
  get "/organizations/:organization_id/copilot-spaces/:space_number",
      operation_id: "copilot-spaces/get-for-org",
      read_from_replicas: true do
    org = find_org!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(org)

    space = find_owner_space!(org, params[:space_number])

    control_access :get_organization_copilot_space,
      resource: space,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    enforce_repo_scope_for_space!(space)

    track_spaces_api_event("get_space", space)
    deliver :space_hash, space, user: current_user
  end

  # GET /user/:user_id/copilot-spaces/:space_number
  get "/user/:user_id/copilot-spaces/:space_number",
      operation_id: "copilot-spaces/get-for-user",
      read_from_replicas: true do
    user = find_user!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(user)

    space = find_owner_space!(user, params[:space_number])

    control_access :get_user_copilot_space,
      resource: space,
      challenge: true,
      allow_integrations: false, # Do not allow server-to-server
      # Do not support FGP for user owned spaces due to testing constraints
      # ref https://github.com/github/api-permissions/issues/294
      # ref https://github.com/github/ecosystem-apps/discussions/7725
      allow_user_via_granular_actor: false

    track_spaces_api_event("get_space", space)
    deliver :space_hash, space, user: current_user
  end

  # GET /user/:user_id/copilot-spaces
  get "/user/:user_id/copilot-spaces",
      operation_id: "copilot-spaces/list-for-user",
      read_from_replicas: true do
    user = find_user!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(user)

    return deliver_error 404, message: "Not found" unless individual_access_enabled?(user)

    control_access :list_user_copilot_spaces,
      resource: user,
      challenge: true,
      allow_integrations: false, # Do not allow server-to-server
      # Do not support FGP for user owned spaces due to testing constraints
      # ref https://github.com/github/api-permissions/issues/294
      # ref https://github.com/github/ecosystem-apps/discussions/7725
      allow_user_via_granular_actor: false

    per_page = parse_per_page(params)
    current_cursor = parse_pagination_cursor_or_error!(params, per_page)
    spaces_plus_one = find_user_spaces(user, current_cursor)

    track_spaces_api_event("list_spaces", nil, owner_type: "User")
    handle_paginated_list_response(spaces_plus_one, current_cursor, per_page)
  end

  # POST /organizations/:organization_id/copilot-spaces
  post "/organizations/:organization_id/copilot-spaces", operation_id: "copilot-spaces/create-for-org", read_from_replicas: true do
    org = find_org!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(org)

    control_access :create_organization_copilot_space,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    create_and_save_copilot_space(org)
  end

  # POST /user/:user_id/copilot-spaces
  post "/user/:user_id/copilot-spaces", operation_id: "copilot-spaces/create-for-user", read_from_replicas: true do
    user = find_user!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(user)

    return deliver_error 404, message: "Not found" unless individual_access_enabled?(user)

    control_access :create_user_copilot_space,
      resource: user,
      challenge: true,
      allow_integrations: false, # Do not allow server-to-server
      # Do not support FGP for user owned spaces due to testing constraints
      # ref https://github.com/github/api-permissions/issues/294
      # ref https://github.com/github/ecosystem-apps/discussions/7725
      allow_user_via_granular_actor: false

    create_and_save_copilot_space(user)
  end

  # PUT /organizations/:organization_id/copilot-spaces/:space_number
  put "/organizations/:organization_id/copilot-spaces/:space_number", operation_id: "copilot-spaces/update-for-org", read_from_replicas: true do
    org = find_org!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(org)

    space = find_owner_space!(org, params[:space_number])

    control_access :update_organization_copilot_space,
      resource: space,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    enforce_repo_scope_for_space!(space)

    update_and_save_copilot_space(space)
  end

  # DELETE /organizations/:organization_id/copilot-spaces/:space_number
  delete "/organizations/:organization_id/copilot-spaces/:space_number", operation_id: "copilot-spaces/delete-for-org", read_from_replicas: true do
    org = find_org!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(org)

    space = find_owner_space!(org, params[:space_number])

    control_access :manage_organization_copilot_space,
      resource: space,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    enforce_repo_scope_for_space!(space)

    delete_and_destroy_copilot_space(space)
  end

  # PUT /user/:user_id/copilot-spaces/:space_number
  put "/user/:user_id/copilot-spaces/:space_number", operation_id: "copilot-spaces/update-for-user", read_from_replicas: true do
    user = find_user!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(user)

    space = find_owner_space!(user, params[:space_number])

    control_access :update_user_copilot_space,
      resource: space,
      challenge: true,
      allow_integrations: false, # Do not allow server-to-server
      # Do not support FGP for user owned spaces due to testing constraints
      # ref https://github.com/github/api-permissions/issues/294
      # ref https://github.com/github/ecosystem-apps/discussions/7725
      allow_user_via_granular_actor: false

    update_and_save_copilot_space(space)
  end

  # DELETE /user/:user_id/copilot-spaces/:space_number
  delete "/user/:user_id/copilot-spaces/:space_number", operation_id: "copilot-spaces/delete-for-user", read_from_replicas: true do
    user = find_user!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(user)

    space = find_owner_space!(user, params[:space_number])

    control_access :manage_user_copilot_space,
      resource: space,
      challenge: true,
      allow_integrations: false, # Do not allow server-to-server
      # Do not support FGP for user owned spaces due to testing constraints
      # ref https://github.com/github/api-permissions/issues/294
      # ref https://github.com/github/ecosystem-apps/discussions/7725
      allow_user_via_granular_actor: false

    delete_and_destroy_copilot_space(space)
  end

  private

  # ========================================================================
  # FEATURE FLAG AND VALIDATION HELPERS
  # ========================================================================

  # Check if copilot spaces API is enabled for the given resource or current user
  #
  # @param resource [User|Organization] The resource to check feature flag for
  # @return [Boolean] true if feature is enabled
  def copilot_spaces_api_enabled?(resource)
    FeatureFlag.vexi.enabled?("copilot_spaces_api", resource, default: false) ||
      FeatureFlag.vexi.enabled?("copilot_spaces_api", current_user, default: false)
  end

  # ========================================================================
  # PAGINATION RESPONSE HANDLING
  # ========================================================================

  # Handle paginated list response for copilot spaces API
  #
  # @param spaces_plus_one [Array<CopilotSpace>] spaces with extra record for pagination
  # @param current_cursor [Hash] current cursor state
  # @param per_page [Integer] number of records per page
  # @return [void] delivers the paginated response
  def handle_paginated_list_response(spaces_plus_one, current_cursor, per_page)
    # Calculate pagination state using the module
    pagination_result = calculate_pagination_response(spaces_plus_one, current_cursor, per_page)

    # Populate @links with cursor-based pagination. Using @links (instead of
    # setting response.headers["Link"] directly) prevents Api::App's deliver
    # from auto-emitting page=-based Link headers, and avoids having our header
    # overwritten by @links.to_header later in the delivery chain.
    cursors = pagination_result[:cursors]
    if cursors[:after]
      @links.add_current({ after: cursors[:after], before: nil, per_page: per_page, page: nil }, rel: "next")
    end
    if cursors[:before]
      @links.add_current({ before: cursors[:before], after: nil, per_page: per_page, page: nil }, rel: "prev")
    end

    # Set transient attrs on each space so visible_resources filters correctly
    pagination_result[:spaces].each do |space|
      space.current_user = current_user
      space.cap_filter = cap_filter
    end

    # Deliver the response using the API serializer
    deliver :copilot_spaces_list_hash, { spaces: pagination_result[:spaces] }, user: current_user, global_id_selection: global_id_selection
  end

  # ========================================================================
  # SPACE QUERYING AND PERMISSIONS
  # ========================================================================

  def find_org_spaces(org, cursor)
    org_visible_spaces = CopilotSpace.visible_query(current_user, cap_filter, org).where(owner: org)
    org_visible_spaces = apply_repo_scope_filter_to_scope(org_visible_spaces, target: org)
    find_spaces_for_owner(org_visible_spaces, cursor)
  end

  def find_user_spaces(user, cursor)
    # If the current user is viewing their own spaces, show all their spaces
    if current_user == user
      scope = CopilotSpace.where(owner: user)
      scope = apply_repo_scope_filter_to_scope(scope, target: user)
      find_spaces_for_owner(scope, cursor)
    else
      # For viewing another user's spaces, use the visible_user_spaces scope for security filtering
      # Note that we are not checking each space readable_by? as
      # the scope already does the necessary filtering
      scope = CopilotSpace.visible_user_spaces(current_user, user)
      scope = apply_repo_scope_filter_to_scope(scope, target: user)
      find_spaces_for_owner(scope, cursor)
    end
  end

  # ========================================================================
  # SPACE CRUD OPERATIONS AND DATA HANDLING
  # ========================================================================

  def create_and_save_copilot_space(owner)
    data = parse_copilot_space_params

    reject_disallowed_resource_types!(data)

    enforce_repo_scope_for_submitted_resources!(
      target: owner,
      resources_attributes: data[:resources_attributes],
    )

    copilot_space = CopilotSpace.new(data)
    copilot_space.owner = owner
    copilot_space.creator = current_user
    copilot_space.current_user = current_user
    copilot_space.cap_filter = cap_filter if respond_to?(:cap_filter)

    track_spaces_api_write_event(action: :create, event_name: "create_space", space: copilot_space)

    save_copilot_space(copilot_space, status: 201)
  end

  def update_and_save_copilot_space(space)
    data = parse_copilot_space_params

    reject_disallowed_resource_types!(data)

    enforce_repo_scope_for_submitted_resources!(
      target: space.owner,
      resources_attributes: data[:resources_attributes],
    )

    # Check if base_role is being changed and require admin permissions
    if data.key?(:base_role) && data[:base_role].present?
      new_base_role = data[:base_role].to_s
      if new_base_role != space.base_role.to_s
        # Changing base_role requires admin permissions
        return deliver_error(403, message: "You must be an admin to change the base_role") unless space.adminable_by?(current_user)
      end
    end

    # For REST API, handle full resource replacement
    if data.key?(:resources_attributes)
      # Determine which existing resources the caller can see
      visible_resources = space.visible_resources

      if data[:resources_attributes].empty?
        # Empty array means clear all visible resources; preserve hidden ones
        data[:resources_attributes] = visible_resources.map do |resource|
          { id: resource.id, _destroy: true }
        end
      else
        # Non-empty array means replace visible resources with new ones
        new_resources = data[:resources_attributes].map do |resource_attrs|
          # Ensure this is treated as a new resource (no id)
          resource_attrs.except(:id, :_destroy)
        end

        # Mark only visible existing resources for destruction
        existing_resources_for_destruction = visible_resources.map do |resource|
          { id: resource.id, _destroy: true }
        end

        # Combine destruction of visible with creation of new (hidden are untouched)
        data[:resources_attributes] = existing_resources_for_destruction + new_resources
      end

      # Re-filter the resources_attributes to allow id and _destroy for the internally generated ones
      data[:resources_attributes] = filter_resources_attributes(data[:resources_attributes], allow_id_and_destroy: true)
    end
    # If resources_attributes key is not present, don't modify resources at all

    # Update space attributes, preserving owner and creator
    space.assign_attributes(data)
    space.current_user = current_user
    space.cap_filter = cap_filter if respond_to?(:cap_filter)

    track_spaces_api_write_event(action: :update, event_name: "update_space", space: space)

    save_copilot_space(space, status: 200)
  end

  def delete_and_destroy_copilot_space(space)
    space.current_user = current_user
    space.cap_filter = cap_filter if respond_to?(:cap_filter)

    track_spaces_api_write_event(action: :delete, event_name: "delete_space", space: space)

    with_write do
      if space.destroy
        status 204
      else
        error_messages = format_error_messages(space.errors)
        GitHub.logger.warn("Space delete failed", "gh.user.id" => current_user&.id, "gh.copilot.copilot_space.id" => space.id, "error" => error_messages.values.join(", "))
        deliver_error 422, errors: error_messages
      end
    end
  end

  def parse_copilot_space_params
    ensure_json_request_body!
    data = receive_with_openapi
    filter_copilot_space_params(data)
  end

  def save_copilot_space(copilot_space, status: 200)
    with_write do
      action = copilot_space.persisted? ? :update : :create
      saved = CopilotSpace::Persistence.save(
        copilot_space: copilot_space,
        current_user: current_user,
        cap_filter: cap_filter,
        action: action
      )

      if saved
        deliver :space_hash, copilot_space, user: current_user, status: status
      else
        # Clear autogenerated number that wouldn't exist in database for new records
        copilot_space.number = nil unless copilot_space.persisted?
        error_messages = format_error_messages(copilot_space.errors)
        GitHub.logger.warn("Space #{action} failed", "gh.user.id" => current_user&.id, "gh.copilot.copilot_space.id" => copilot_space.id, "error" => error_messages.values.join(", "))
        deliver_error 422, errors: error_messages
      end
    end
  end

  def find_owner_space!(owner, space_number)
    space = CopilotSpace.find_by(owner: owner, number: parse_space_number!(space_number))
    deliver_error!(404) unless space
    space.current_user = current_user
    space.cap_filter = cap_filter if respond_to?(:cap_filter)
    space
  end

  def filter_copilot_space_params(data)
    # Define allowed parameters similar to internal API
    allowed_params = %w[
      name
      description
      general_instructions
      base_role
    ]

    filtered = data.slice(*allowed_params)

    # Convert base_role from API format to internal format
    if filtered["base_role"].present?
      internal_role = api_base_role_to_internal(filtered["base_role"])
      if internal_role.nil?
        # Invalid role will be caught by model validation
        filtered["base_role"] = filtered["base_role"]
      else
        filtered["base_role"] = internal_role.to_s
      end
    end

    # Handle resources if key is present (even if empty array)
    if data.key?("resources_attributes")
      # For create operations, don't allow id/destroy; for updates they'll be added internally when needed
      filtered["resources_attributes"] = filter_resources_attributes(data["resources_attributes"] || [], allow_id_and_destroy: false)
    end

    # Convert string keys to symbols for ActiveRecord
    filtered.transform_keys(&:to_sym)
  end

  def reject_disallowed_resource_types!(data)
    resources = data[:resources_attributes] || data["resources_attributes"]
    return unless resources.is_a?(Array)

    bad = resources.find do |r|
      next false unless r.is_a?(Hash)
      type = (r[:resource_type] || r["resource_type"]).to_s
      Api::CopilotSpacesResources::DISALLOWED_RESOURCE_TYPES.include?(type)
    end

    return unless bad

    type = (bad[:resource_type] || bad["resource_type"]).to_s
    deliver_error!(422, message: "Resource type '#{type}' is not supported via this endpoint")
  end

  def filter_resources_attributes(resources, allow_id_and_destroy: false)
    return [] unless resources.is_a?(Array)

    filtered_resources = resources.map do |resource|
      next unless resource.is_a?(Hash)

      # For REST API, only allow resource creation parameters (no id or _destroy for patching)
      base_allowed_params = %w[
        resource_type
        copilot_chat_attachment_id
        metadata
      ]

      filtered_resource = resource.slice(*base_allowed_params)

      # Allow id and _destroy only when specifically permitted (for internal use during updates)
      if allow_id_and_destroy
        if resource[:id] || resource["id"]
          filtered_resource["id"] = resource[:id] || resource["id"]
        end

        if resource[:_destroy] || resource["_destroy"]
          filtered_resource["_destroy"] = resource[:_destroy] || resource["_destroy"]
        end
      end

      # Handle metadata if present
      if resource["metadata"].present? && resource["metadata"].is_a?(Hash)
        allowed_metadata_params = %w[
          repository_id
          file_path
          sha
          text
          name
          number
          media_type
          url
          height
          width
          size
        ]
        filtered_resource["metadata"] = resource["metadata"].slice(*allowed_metadata_params)
      end

      filtered_resource
    end

    filtered_resources.compact
  end

  def format_error_messages(errors)
    result = {}
    errors.each do |error|
      key = error.attribute.to_s.underscore
      next if INTERNAL_ERROR_ATTRIBUTES.include?(key.split(".").last)

      result[key] = error.message
    end
    result
  end

  def parse_pagination_cursor_or_error!(params, per_page)
    if params[:after].present? && decode_cursor(params[:after]).nil?
      deliver_error!(422, message: "Invalid cursor")
    end
    if params[:before].present? && decode_cursor(params[:before]).nil?
      deliver_error!(422, message: "Invalid cursor")
    end

    parse_pagination_cursor(params, per_page)
  end

  def individual_access_enabled?(user)
    Copilot::Policies::SpacesIndividualAccess.effective_value(Copilot::User.new(user)) == "enabled"
  end
end
