# typed: true
# frozen_string_literal: true

class Copilot::CopilotSpacesController < ApplicationController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include CopilotSpaces::HydroEventsHelper
  include CopilotSpaces::FeaturePreviewRedirect

  before_action :require_copilot_spaces_feature_enabled
  before_action :login_required
  before_action :try_parse_json_params, only: [:create, :update, :resource_sizes, :validate_url_resources]

  allow_verified_fetch only: [:create, :update, :destroy, :resource_sizes,  :validate_url_resources]

  rescue_from ActiveRecord::RecordNotFound, with: :render_404

  self.react_bundle_name = "custom-copilots"

  # Denied file extensions for resource validation
  DENIED_EXTENSIONS = %w[.png .jpg .jpeg .gif .bmp .svg .webp .ico .tiff .tif].freeze

  def create
    started_at = Time.now
    owner = get_owner(create_custom_copilot_params)
    copilot_space = CopilotSpace.new(create_custom_copilot_params)

    return render_404 unless owner
    copilot_space.owner = owner

    copilot_space.creator = current_user
    assign_user_and_cap(copilot_space)

    if CopilotSpace::Persistence.save(copilot_space:, current_user:, cap_filter:, action: :create)
      Permissions::Granters::RoleGranter.new(actor: current_user, target: copilot_space, role: Role.custom_copilot_admin_role).grant!

      save_elapsed_time = Time.now - started_at

      payload_as_json_start = Time.now
      payload = CopilotSpaces::PageData::CopilotSpace::Payload.call(copilot_space).as_json
      payload_as_json_elapsed_time_seconds = Time.now - payload_as_json_start
      CopilotSpaces::HydroEventsHelper.instrument_hydro_events(:create, copilot_space, current_user, cap_filter, data: {
        controller: self.class.name,
        save_elapsed_time_seconds: save_elapsed_time,
        payload_as_json_elapsed_time_seconds: payload_as_json_elapsed_time_seconds,
      })

      render json: payload, status: :ok
    else
      # We need to set the number to nil here because the number is generated in the before_validation callback
      # This number would not exist in the database since the record was not saved.
      copilot_space.number = nil
      CopilotSpaces::HydroEventsHelper.instrument_hydro_events(:create, copilot_space, current_user, cap_filter, data: {
        controller: self.class.name,
        save_elapsed_time_seconds: Time.now - started_at,
      })
      render json: { errorMessages: format_error_messages(copilot_space.errors) }, status: :unprocessable_entity
    end
  end

  def update
    return render_404 unless copilot_space.editable_by?(current_user)

    started_at = Time.now
    params_to_update = update_custom_copilot_params

    # Handle duplicate github file resources before assigning to the model
    if params_to_update[:resources_attributes].present?
      handle_duplicate_github_file_resources(params_to_update[:resources_attributes])
    end

    copilot_space.assign_attributes(params_to_update)
    assign_user_and_cap(copilot_space)

    if CopilotSpace::Persistence.save(copilot_space:, current_user:, cap_filter:, action: :update)
      save_elapsed_time = Time.now - started_at
      payload_as_json_start = Time.now
      payload = CopilotSpaces::PageData::CopilotSpace::Payload.call(copilot_space).as_json
      payload_as_json_elapsed_time_seconds = Time.now - payload_as_json_start

      CopilotSpaces::HydroEventsHelper.instrument_hydro_events(:update, copilot_space, current_user, cap_filter, data: {
        controller: self.class.name,
        save_elapsed_time_seconds: save_elapsed_time,
        payload_as_json_elapsed_time_seconds: payload_as_json_elapsed_time_seconds,
      })

      render json: payload, status: :ok
    else
      CopilotSpaces::HydroEventsHelper.instrument_hydro_events(:update, copilot_space, current_user, cap_filter, data: {
        controller: self.class.name,
        save_elapsed_time_seconds: Time.now - started_at,
      })
      render json: { errorMessages: format_error_messages(copilot_space.errors) }, status: :unprocessable_entity
    end
  end

  def destroy
    if params[:owner].present? && params[:number].present?
      owner = User.find_by_login(params[:owner])
      return render_404 unless owner
      copilot_space = CopilotSpace.find_by!(number: params[:number], owner: owner)
    else
      copilot_space = CopilotSpace.find_by!(id: params[:id])
    end

    return render_404 unless copilot_space.adminable_by?(current_user)

    started_at = Time.now

    copilot_space.destroy!
    CopilotSpaces::HydroEventsHelper.instrument_hydro_events(:delete, copilot_space, current_user, cap_filter, data: {
      controller: self.class.name,
      save_elapsed_time_seconds: Time.now - started_at,
    })
    head :ok
  end

  def validate_url_resources # rubocop:todo GitHub/UseRestfulActions
    started_at = Time.now
    resources = handle_url_resources(params[:resources_attributes])
    status = :ok

    valid_resources = []
    resource_errors = []
    owner = params[:space_owner].present? ? User.find_by_login(params[:space_owner]) : current_user

    repo_ids = resources.map { |r| r[:metadata][:repository_id] }.uniq
    repos = Repository.where(id: repo_ids).index_by(&:id)

    resources.map do |resource|
      ccr = CopilotSpaceResource.new(resource_type: resource[:resource_type], metadata: resource[:metadata])
      space = CopilotSpace.new(current_user:, cap_filter:, owner: owner)
      ccr.copilot_space = space
      validator = CopilotSpace::CapValidator.new(current_user:, copilot_space: space, cap_filter:)
      validator.validate_resource_repository_access(ccr, repos[ccr.repository_id])

      # When the flag is disabled repository access will be validated by code
      # in the CopilotSpaceResource model
      if ccr.valid?
        metadata = ccr.parsed_metadata.to_url_validation_payload
        metadata[:sizePercentage] = ccr.size_percentage
        metadata[:id] = resource[:id]
        valid_resources << metadata
      else
        status = :unprocessable_entity
        resource_errors << { id: resource[:id], errors: format_error_messages(ccr.errors) }
      end
    end

    payload = status == :ok ? valid_resources : resource_errors

    CopilotSpaces::HydroEventsHelper.instrument_generic_event("validate_url_resources", current_user, nil, data: {
      controller: self.class.name,
      elapsed_time_seconds: Time.now - started_at,
      resource_count: resources.size,
      status: status,
    })
    render json: payload, status: status
  end

  def resource_sizes # rubocop:disable GitHub/UseRestfulActions
    # Calculating the size percentage of the resource requires the current user because we check a feature flag
    # to determine their max size on CopilotSpace.max_content_size
    #
    # So we need to create a CopilotSpace and set it on the resource so the resource has access to the current user
    copilot_space = CopilotSpace.new(current_user:, cap_filter:)

    started_at = Time.now
    repository_ids_from_params = resource_sizes_params.filter_map do |resource_params|
      resource_params[:metadata][:repository_id]
    end
    authorized_repos_indexed_by_id = copilot_space.authorized_repositories(repository_ids_from_params, viewer: current_user, cap_filter:).index_by(&:id)

    # Group all resources by type for different processing
    all_resources = resource_sizes_params.each_with_index.map do |resource_params, index|
      resource = CopilotSpaceResource.new(resource_params.except(:_destroy, :id).merge(id: index))
      resource.copilot_space = copilot_space
      { resource: resource, id_from_frontend: resource_params[:id] }
    end

    # Filter out unauthorized resources and check for unsupported files
    unsupported_files = []
    authorized_resources = all_resources.select do |item|
      resource = item[:resource]

      # check if the github file resource is serializable by twirp
      if resource.github_file_resource_type? && (resource.twirp_resource.nil? || denied_file_extension?(resource.metadata["file_path"]))
        file_path = resource.metadata["file_path"]
        unsupported_files << file_path
      end

      # Make sure resources that require access to a repo are authorized for this use
      if (
        !resource.free_text_resource_type? &&
        !resource.uploaded_text_file_resource_type? &&
        !resource.media_content_resource_type? &&
        !authorized_repos_indexed_by_id[resource.repository_id]
      )
        false # exclude unauthorized resources
      else
        true
      end
    end

    # Separate GitHub file resources for batch processing
    github_file_resources, non_file_resources = authorized_resources.partition { |item| item[:resource].github_file_resource_type? }

    # Returns hash where the keys are the resource ids from the frontend, and the value is a float size percentage
    #
    #  {'id-from-frontend': 0.1249123}
    resource_sizes_payload = {}

    # Process non-file resources individually (these are fast)
    non_file_resources.each do |item|
      resource = item[:resource]
      id_from_frontend = item[:id_from_frontend]
      resource_valid = true
      if resource.media_content_resource_type? || resource.uploaded_text_file_resource_type?
        # This check ensures that users cannot change the chat attachment id in the post request to see the resource size for
        # attachments that they did not upload. If the chat attachment exists and was not uploaded by the current user, just return 0.
        resource_valid = resource.valid?
      end
      resource_sizes_payload[id_from_frontend] = resource_valid ? resource.size_percentage : 0
    end

    # Batch process GitHub file resources grouped by repository
    max_content_size = CopilotSpace.max_content_size(current_user).to_f
    github_file_resources_by_repo = github_file_resources.group_by { |item| item[:resource].repository_id }

    github_file_resources_by_repo.each do |repository_id, items|
      repo = authorized_repos_indexed_by_id.fetch(repository_id)
      file_resources = items.map { |item| item[:resource] }

      file_collection = CopilotSpace::GitHubFileCollection.new(
        max_content_size: max_content_size,
        repository: repo,
        file_resources: file_resources,
      )
      file_collection.git_info.each_with_index do |file_info, index|
        item = items[index]
        id_from_frontend = item[:id_from_frontend]
        resource_sizes_payload[id_from_frontend] = file_info.size_percentage
      end
    end

    if unsupported_files.any?
      CopilotSpaces::HydroEventsHelper.instrument_generic_event("resource_sizes", current_user, nil, data: {
        controller: self.class.name,
        elapsed_time_seconds: Time.now - started_at,
        resource_count: resource_sizes_params.size,
        unsupported_files_count: unsupported_files.size,
        copilot_spaces_fast_git_resources: true,
        status: :unprocessable_entity,
      })
      return render json: { errorMessages: { base: "unsupported_file_type", files: unsupported_files } }, status: :unprocessable_entity
    end

    CopilotSpaces::HydroEventsHelper.instrument_generic_event("resource_sizes", current_user, nil, data: {
      controller: self.class.name,
      elapsed_time_seconds: Time.now - started_at,
      resource_count: resource_sizes_params.size,
      copilot_spaces_fast_git_resources: true,
      status: :ok,
    })

    render json: resource_sizes_payload, status: :ok
  end

  private

  # Check if a file path has an extension from the denylist
  def denied_file_extension?(file_path)
    return false if file_path.blank?

    extension = File.extname(file_path.downcase)
    DENIED_EXTENSIONS.include?(extension)
  end

  # Filter out any github file resources that would be duplicates
  def handle_duplicate_github_file_resources(resources_attributes)
    return unless resources_attributes.present?

    # Only process new github file resources (those without IDs)
    new_github_file_resources = resources_attributes.select do |resource|
      resource[:id].blank? && resource[:resource_type] == CopilotSpaceResource::Constants::GITHUB_FILE
    end

    return if new_github_file_resources.empty?

    # Find existing github file resources for this custom copilot
    existing_resources = copilot_space.resources
      .where(resource_type: :github_file)
      .select([:id, :metadata])
      .to_a

    # Create a key generator lambda for consistent key generation
    key_generator = ->(repo_id, file_path) { "#{repo_id}:#{file_path}" if repo_id.present? && file_path.present? }

    # Create a lookup hash for quick duplicate checking
    existing_lookup = {}
    existing_resources.each do |resource|
      repo_id = resource.metadata["repository_id"]
      file_path = resource.metadata["file_path"]
      next unless repo_id.present? && file_path.present?

      key = key_generator.call(repo_id, file_path)
      existing_lookup[key] = true
    end

    new_github_file_resources.each do |resource|
      repository_id = resource[:metadata][:repository_id]
      file_path = resource[:metadata][:file_path]

      next unless repository_id.present? && file_path.present?

      # Check if this would be a duplicate
      key = key_generator.call(repository_id, file_path)
      resources_attributes.delete(resource) if existing_lookup[key]
    end

    resources_attributes
  end

  def handle_url_resources(resources_attributes)
    return unless resources_attributes.present?

    github_url_resources = resources_attributes.select do |resource|
      CopilotSpaceResource::URL_RESOURCES.include?(resource[:resource_type])
    end

    return if github_url_resources.empty?

    github_url_resources.each do |resource|
      # use the repo and owner from the metadata to find the repo id
      owner_login = resource[:metadata][:owner]
      repo_name = resource[:metadata][:repo]
      repository = Repository.nwo("#{owner_login}/#{repo_name}")
      if repository
        resource[:metadata][:repository_id] = repository.id
      else
        # TODO: if the repo is not found, we should return an error to the user as part of validate_url_resources
        resources_attributes.delete(resource)
      end

      resources_attributes
    end
  end

  def format_error_messages(errors)
    errors.messages.transform_values do |error_messages|
      # This converts the error messages from an array of strings, to a single
      # string sentence for easy display in the UI
      error_messages.to_sentence
    end
  end

  sig { returns(CopilotSpace) }
  memoize def copilot_space
    CopilotSpace.for_owner_login_and_number!(params[:owner], params[:number])
  end

  memoize def sso_orgs
    saml_for_user.protected_organizations.map { |org| { id: org.id.to_s, name: org.name, login: org.display_login } }
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def shared_custom_copilot_params
    [
      :name,
      :description,
      :general_instructions,
      :icon_type,
      :icon_color,
      :visibility,
      :base_role,
      resources_attributes: resources_attributes_params
    ]
  end

  def resource_sizes_params
    params.expect(resources: [resources_attributes_params])
  end

  def resources_attributes_params
    [
      :_destroy,
      :id,
      :copilot_chat_attachment_id,
      :resource_type,
      { metadata:
        [
          :repository_id,
          :file_path,
          :sha,
          :text,
          :name,
          :number,
          :media_type, # only for image resources
          :url, # only for image resources
          :height, # only for image resources
          :width, # only for image resources
          :size, # only for image resources
        ]
      }
    ]
  end

  def update_custom_copilot_params
    permitted_params = params
      .require(:custom_copilot)
      .permit(*shared_custom_copilot_params)

    disallowed_resource_types = [].tap do |types|
      types << CopilotSpaceResource::Constants::MEDIA_CONTENT unless user_feature_enabled?(:copilot_custom_copilots_images)
    end

    if disallowed_resource_types.present? && permitted_params[:resources_attributes]
      permitted_params[:resources_attributes].reject! do |resource|
        disallowed_resource_types.include?(resource[:resource_type])
      end
    end

    permitted_params
  end

  def create_custom_copilot_params
    permitted_params = [:owner_id, :owner_type] + shared_custom_copilot_params

    filtered_params = params
      .require(:custom_copilot)
      .permit(*permitted_params).tap do |params|
        if params[:resources_attributes]
          params[:resources_attributes].each do |resource|
            resource.delete(:id)
          end
        end
      end

    disallowed_resource_types = [].tap do |types|
      types << CopilotSpaceResource::Constants::MEDIA_CONTENT unless user_feature_enabled?(:copilot_custom_copilots_images)
    end

    if disallowed_resource_types.present? && filtered_params[:resources_attributes]
      filtered_params[:resources_attributes].reject! do |resource|
        disallowed_resource_types.include?(resource[:resource_type])
      end
    end

    filtered_params
  end

  def assign_user_and_cap(copilot_space)
    copilot_space.current_user = current_user
    copilot_space.cap_filter = cap_filter
  end

  def get_owner(params)
    return current_user unless params[:owner_type] && params[:owner_id]

    if params[:owner_type] ==  "Organization"
      return Organization.find_by!(id: params[:owner_id])
    end

    current_user
  end
end
