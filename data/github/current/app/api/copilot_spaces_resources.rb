# typed: true
# frozen_string_literal: true

class Api::CopilotSpacesResources < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::Serializer
  include CopilotSpaces::RoleMapping
  include CopilotSpaces::ApiAnalytics
  include CopilotSpaces::ResourceFiltering
  include CopilotSpaces::ApiRequestValidation
  include CopilotSpaces::RepoScopeAuthz

  DISALLOWED_RESOURCE_TYPES = [
    CopilotSpaceResource::Constants::UPLOADED_TEXT_FILE,
    CopilotSpaceResource::Constants::MEDIA_CONTENT,
  ].freeze

  INTERNAL_ERROR_ATTRIBUTES = %w[slug].freeze
  METADATA_ERROR_ATTRIBUTES = {
    "file_extension" => "file_path",
  }.freeze
  ALLOWED_METADATA_PARAMS = %w[
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
  ].freeze

  # ========================================================================
  # Organization-owned space endpoints
  # ========================================================================

  # GET /organizations/:organization_id/copilot-spaces/:space_number/resources
  get "/organizations/:organization_id/copilot-spaces/:space_number/resources",
      operation_id: "copilot-spaces/list-resources-for-org",
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

    track_spaces_api_event("list_resources", space)
    deliver :copilot_space_resources_list_hash, { resources: space.visible_resources }
  end

  # GET /organizations/:organization_id/copilot-spaces/:space_number/resources/:space_resource_id
  get "/organizations/:organization_id/copilot-spaces/:space_number/resources/:space_resource_id",
      operation_id: "copilot-spaces/get-resource-for-org",
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

    resource = find_visible_resource!(space, params[:space_resource_id])
    track_spaces_api_event("get_resource", space, resource_type: resource.resource_type, resource_id: resource.id)
    deliver :copilot_space_resource_hash, resource
  end

  # POST /organizations/:organization_id/copilot-spaces/:space_number/resources
  post "/organizations/:organization_id/copilot-spaces/:space_number/resources", read_from_replicas: true,
       operation_id: "copilot-spaces/create-resource-for-org" do
    org = find_org!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(org)

    space = find_owner_space!(org, params[:space_number])

    control_access :update_organization_copilot_space,
      resource: space,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    enforce_repo_scope_for_space!(space)

    create_resource(space)
  end

  # PUT /organizations/:organization_id/copilot-spaces/:space_number/resources/:space_resource_id
  put "/organizations/:organization_id/copilot-spaces/:space_number/resources/:space_resource_id", read_from_replicas: true,
      operation_id: "copilot-spaces/update-resource-for-org" do
    org = find_org!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(org)

    space = find_owner_space!(org, params[:space_number])

    control_access :update_organization_copilot_space,
      resource: space,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    enforce_repo_scope_for_space!(space)

    resource = find_visible_resource!(space, params[:space_resource_id])
    update_resource(space, resource)
  end

  # DELETE /organizations/:organization_id/copilot-spaces/:space_number/resources/:space_resource_id
  delete "/organizations/:organization_id/copilot-spaces/:space_number/resources/:space_resource_id", read_from_replicas: true,
         operation_id: "copilot-spaces/delete-resource-for-org" do
    org = find_org!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(org)

    space = find_owner_space!(org, params[:space_number])

    control_access :update_organization_copilot_space,
      resource: space,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    enforce_repo_scope_for_space!(space)

    resource = find_visible_resource!(space, params[:space_resource_id])
    delete_resource(space, resource)
  end

  # ========================================================================
  # User-owned space endpoints
  # ========================================================================

  # GET /user/:user_id/copilot-spaces/:space_number/resources
  get "/user/:user_id/copilot-spaces/:space_number/resources",
      operation_id: "copilot-spaces/list-resources-for-user",
      read_from_replicas: true do
    user = find_user!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(user)
    return deliver_error 404, message: "Not found" unless individual_access_enabled?(user)

    space = find_owner_space!(user, params[:space_number])

    control_access :get_user_copilot_space,
      resource: space,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    track_spaces_api_event("list_resources", space)
    deliver :copilot_space_resources_list_hash, { resources: space.visible_resources }
  end

  # GET /user/:user_id/copilot-spaces/:space_number/resources/:space_resource_id
  get "/user/:user_id/copilot-spaces/:space_number/resources/:space_resource_id",
      operation_id: "copilot-spaces/get-resource-for-user",
      read_from_replicas: true do
    user = find_user!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(user)
    return deliver_error 404, message: "Not found" unless individual_access_enabled?(user)

    space = find_owner_space!(user, params[:space_number])

    control_access :get_user_copilot_space,
      resource: space,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    resource = find_visible_resource!(space, params[:space_resource_id])
    track_spaces_api_event("get_resource", space, resource_type: resource.resource_type, resource_id: resource.id)
    deliver :copilot_space_resource_hash, resource
  end

  # POST /user/:user_id/copilot-spaces/:space_number/resources
  post "/user/:user_id/copilot-spaces/:space_number/resources", read_from_replicas: true,
       operation_id: "copilot-spaces/create-resource-for-user" do
    user = find_user!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(user)
    return deliver_error 404, message: "Not found" unless individual_access_enabled?(user)

    space = find_owner_space!(user, params[:space_number])

    control_access :update_user_copilot_space,
      resource: space,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    create_resource(space)
  end

  # PUT /user/:user_id/copilot-spaces/:space_number/resources/:space_resource_id
  put "/user/:user_id/copilot-spaces/:space_number/resources/:space_resource_id", read_from_replicas: true,
      operation_id: "copilot-spaces/update-resource-for-user" do
    user = find_user!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(user)
    return deliver_error 404, message: "Not found" unless individual_access_enabled?(user)

    space = find_owner_space!(user, params[:space_number])

    control_access :update_user_copilot_space,
      resource: space,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    resource = find_visible_resource!(space, params[:space_resource_id])
    update_resource(space, resource)
  end

  # DELETE /user/:user_id/copilot-spaces/:space_number/resources/:space_resource_id
  delete "/user/:user_id/copilot-spaces/:space_number/resources/:space_resource_id", read_from_replicas: true,
         operation_id: "copilot-spaces/delete-resource-for-user" do
    user = find_user!

    return deliver_error 404, message: "Not found" unless copilot_spaces_api_enabled?(user)
    return deliver_error 404, message: "Not found" unless individual_access_enabled?(user)

    space = find_owner_space!(user, params[:space_number])

    control_access :update_user_copilot_space,
      resource: space,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    resource = find_visible_resource!(space, params[:space_resource_id])
    delete_resource(space, resource)
  end

  private

  # ========================================================================
  # Feature flag and validation helpers
  # ========================================================================

  def copilot_spaces_api_enabled?(resource)
    FeatureFlag.vexi.enabled?("copilot_spaces_api", resource, default: false) ||
      FeatureFlag.vexi.enabled?("copilot_spaces_api", current_user, default: false)
  end

  def individual_access_enabled?(user)
    Copilot::Policies::SpacesIndividualAccess.effective_value(Copilot::User.new(user)) == "enabled"
  end

  # ========================================================================
  # Finders
  # ========================================================================

  def find_owner_space!(owner, space_number)
    space = CopilotSpace.where(owner: owner).find_by(number: parse_space_number!(space_number))
    deliver_error!(404) unless space
    space.current_user = current_user
    space.cap_filter = cap_filter
    space
  end

  def find_visible_resource!(space, space_resource_id)
    resource = space.resources.find_by(id: space_resource_id)
    deliver_error!(404) unless resource
    deliver_error!(404) unless resource_visible?(resource, cap_filter, current_user)
    resource
  end

  # ========================================================================
  # Resource CRUD operations
  # ========================================================================

  def create_resource(space)
    data = parse_resource_params

    resource_type = data[:resource_type]

    if DISALLOWED_RESOURCE_TYPES.include?(resource_type)
      return deliver_error 422, message: "Resource type '#{resource_type}' is not supported via this endpoint"
    end

    enforce_repo_scope_for_submitted_resources!(
      target: space.owner,
      resources_attributes: [data],
    )

    space.current_user = current_user
    space.cap_filter = cap_filter

    with_write do
      existing = find_duplicate_resource(space, resource_type, data[:metadata])
      if existing
        return deliver_error 422, message: "Resource already exists in this space", errors: { resource_id: existing.id }
      end

      # Build the resource via nested attributes to leverage existing validations
      space.resources_attributes = [data]
      new_resource = space.resources.detect(&:new_record?)

      # File existence is an API-contract concern, checked here rather than in
      # the model (see CopilotSpaceResource#validate_metadata_schema for why).
      if new_resource&.github_file_resource_type? && !new_resource.file_exists?
        return deliver_error 422, errors: { "resources.resource": "not found" }
      end

      if space.total_content_size_exceeds_limit?
        return deliver_error 422,
          message: "Adding this resource would exceed the space's content size limit",
          errors: { content_size: "exceeds limit" }
      end

      saved = CopilotSpace::Persistence.save(
        copilot_space: space,
        current_user: current_user,
        cap_filter: cap_filter,
        action: :update
      )

      if saved
        track_spaces_api_write_event(
          action: :update, event_name: "create_resource", space: space,
          hydro_data: { source: "resources_api", resource_action: "create", resource_type:, resource_id: new_resource.id },
          resource_type:, resource_id: new_resource.id
        )
        deliver :copilot_space_resource_hash, new_resource, status: 201
      else
        error_messages = format_error_messages(space.errors)
        GitHub.logger.warn("Resource create failed", "gh.user.id" => current_user&.id, "error" => error_messages.values.join(", "))
        deliver_error 422, errors: error_messages
      end
    end
  end

  def update_resource(space, resource)
    # Block updates on file-upload resource types
    if DISALLOWED_RESOURCE_TYPES.include?(resource.resource_type)
      return deliver_error 422, message: "Resource type '#{resource.resource_type}' cannot be updated via this endpoint"
    end

    data = parse_resource_params

    if data.key?(:resource_type) && data[:resource_type].to_s != resource.resource_type
      return deliver_error 422, message: "Resource type cannot be changed after creation"
    end

    if data.key?(:metadata)
      enforce_repo_scope_for_submitted_resources!(
        target: space.owner,
        resources_attributes: [{ resource_type: resource.resource_type, metadata: data[:metadata] }],
      )
    end

    # Build the update via nested attributes
    update_attrs = { id: resource.id }
    update_attrs[:metadata] = data[:metadata] if data.key?(:metadata)

    space.resources_attributes = [update_attrs]
    space.current_user = current_user
    space.cap_filter = cap_filter

    # File existence is an API-contract concern, checked here rather than in
    # the model (see CopilotSpaceResource#validate_metadata_schema for why).
    if resource.github_file_resource_type? && data.key?(:metadata)
      updated = space.resources.detect { |r| r.id == resource.id }
      if updated && !updated.file_exists?
        return deliver_error 422, errors: { "resources.resource": "not found" }
      end
    end

    with_write do
      if space.total_content_size_exceeds_limit?
        return deliver_error 422,
          message: "Updating this resource would exceed the space's content size limit",
          errors: { content_size: "exceeds limit" }
      end

      saved = CopilotSpace::Persistence.save(
        copilot_space: space,
        current_user: current_user,
        cap_filter: cap_filter,
        action: :update
      )

      if saved
        track_spaces_api_write_event(
          action: :update, event_name: "update_resource", space: space,
          hydro_data: { source: "resources_api", resource_action: "update", resource_type: resource.resource_type, resource_id: resource.id },
          resource_type: resource.resource_type, resource_id: resource.id
        )
        resource.reload
        deliver :copilot_space_resource_hash, resource
      else
        error_messages = format_error_messages(space.errors)
        GitHub.logger.warn("Resource update failed", "gh.user.id" => current_user&.id, "error" => error_messages.values.join(", "))
        deliver_error 422, errors: error_messages
      end
    end
  end

  def delete_resource(space, resource)
    space.current_user = current_user
    space.cap_filter = cap_filter

    with_write do
      if resource.destroy
        track_spaces_api_write_event(
          action: :update, event_name: "delete_resource", space: space,
          hydro_data: { source: "resources_api", resource_action: "delete", resource_type: resource.resource_type, resource_id: resource.id },
          resource_type: resource.resource_type, resource_id: resource.id
        )
        status 204
      else
        error_messages = format_error_messages(resource.errors)
        GitHub.logger.warn("Resource delete failed", "gh.user.id" => current_user&.id, "error" => error_messages.values.join(", "))
        deliver_error 422, errors: error_messages
      end
    end
  end

  # ========================================================================
  # Parameter parsing and filtering
  # ========================================================================

  def parse_resource_params
    ensure_json_request_body!
    data = receive_with_openapi
    filter_resource_params(data)
  end

  def filter_resource_params(data)
    allowed_params = %w[resource_type metadata]
    filtered = data.slice(*allowed_params)

    if filtered["metadata"].present? && filtered["metadata"].is_a?(Hash)
      sliced = filtered["metadata"].slice(*ALLOWED_METADATA_PARAMS)
      validate_integer_metadata_fields!(sliced)
      filtered["metadata"] = sanitize_metadata_params(sliced).with_indifferent_access
    end

    filtered.transform_keys(&:to_sym)
  end

  # ========================================================================
  # Deduplication
  # ========================================================================

  def find_duplicate_resource(space, resource_type, metadata)
    return nil unless metadata.present?

    case resource_type
    when CopilotSpaceResource::Constants::GITHUB_FILE
      find_duplicate_github_file(space, metadata)
    when CopilotSpaceResource::Constants::REPOSITORY
      find_duplicate_by_fields(space, :repository, metadata, %w[repository_id])
    when CopilotSpaceResource::Constants::GITHUB_ISSUE
      find_duplicate_by_fields(space, :github_issue, metadata, %w[repository_id number])
    when CopilotSpaceResource::Constants::GITHUB_PULL_REQUEST
      find_duplicate_by_fields(space, :github_pull_request, metadata, %w[repository_id number])
    end
  end

  def find_duplicate_by_fields(space, resource_type, metadata, fields)
    values = fields.map { |f| metadata[f] }
    return nil if values.any?(&:blank?)

    space.resources.where(resource_type: resource_type).find do |resource|
      fields.each_with_index.all? do |field, idx|
        resource.metadata[field].to_s == values[idx].to_s
      end
    end
  end

  def find_duplicate_github_file(space, metadata)
    return nil unless metadata.present?

    repository_id = metadata["repository_id"]
    file_path = metadata["file_path"]
    sha = metadata["sha"]

    return nil unless repository_id.present? && file_path.present?

    existing_resources = space.resources
      .where(resource_type: :github_file)
      .select([:id, :metadata, :resource_type, :custom_copilot_id, :copilot_chat_attachment_id, :created_at, :updated_at])
      .to_a

    # A missing SHA means the resource tracks the repo's default branch, so compare
    # those resources using the current default OID.
    default_sha_by_repo_id = {}
    if sha.blank? || existing_resources.any? { |resource| resource.metadata["sha"].blank? }
      repo_ids = []
      repo_ids << repository_id if sha.blank?
      existing_resources.each do |resource|
        repo_ids << resource.metadata["repository_id"] if resource.metadata["sha"].blank?
      end
      repo_ids = repo_ids.select(&:present?).map(&:to_i).uniq

      if repo_ids.any?
        default_sha_by_repo_id = Repository.where(id: repo_ids).each_with_object({}) do |repo, default_shas|
          default_shas[repo.id] = repo.default_oid
        end
      end
    end
    resolve_default_sha = ->(repo_id) { default_sha_by_repo_id[repo_id.to_i] }

    sha = resolve_default_sha.call(repository_id) if sha.blank?

    existing_resources.find do |resource|
      existing_repo_id = resource.metadata["repository_id"]
      existing_file_path = resource.metadata["file_path"]

      next false unless existing_repo_id.present? && existing_file_path.present?

      existing_sha = resource.metadata["sha"]
      existing_sha = resolve_default_sha.call(existing_repo_id) if existing_sha.blank?
      next false unless sha.present? && existing_sha.present?

      existing_repo_id.to_s == repository_id.to_s &&
        existing_file_path == file_path &&
        existing_sha == sha
    end
  end

  # ========================================================================
  # Metadata sanitization
  # ========================================================================

  INTEGER_METADATA_FIELDS = %w[repository_id number height width size].freeze
  STRING_METADATA_FIELDS = %w[file_path sha text name media_type url].freeze

  def validate_integer_metadata_fields!(metadata)
    INTEGER_METADATA_FIELDS.each do |field|
      next unless metadata.key?(field)
      Integer(metadata[field])
    rescue ArgumentError, TypeError
      deliver_error!(422, message: "Invalid integer value for metadata field '#{field}'")
    end
  end

  def sanitize_metadata_params(metadata)
    sanitized = metadata.dup

    INTEGER_METADATA_FIELDS.each do |field|
      sanitized[field] = Integer(sanitized[field]) if sanitized.key?(field)
    end

    STRING_METADATA_FIELDS.each do |field|
      sanitized[field] = sanitized[field].to_s if sanitized.key?(field)
    end

    if sanitized["file_path"].present?
      sanitized["file_path"] = sanitize_github_file_path(sanitized["file_path"])
    end

    sanitized
  end

  def sanitize_github_file_path(file_path)
    file_path.split(/[?#]/, 2).first
  end

  # ========================================================================
  # Error formatting
  # ========================================================================

  def format_error_messages(errors)
    result = {}
    errors.each do |error|
      key = public_error_key(error.attribute)
      next unless key

      result[key] = error.message
    end
    result
  end

  def public_error_key(attribute)
    key = attribute.to_s.underscore
    key_parts = key.split(".")
    return nil if INTERNAL_ERROR_ATTRIBUTES.include?(key_parts.last)

    return key unless key.start_with?("resources.")

    resource_key = key.delete_prefix("resources.")
    resource_key = METADATA_ERROR_ATTRIBUTES.fetch(resource_key, resource_key)

    if ALLOWED_METADATA_PARAMS.include?(resource_key)
      "metadata.#{resource_key}"
    else
      resource_key
    end
  end
end
