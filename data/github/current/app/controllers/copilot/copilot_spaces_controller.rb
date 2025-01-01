# typed: true
# frozen_string_literal: true

class Copilot::CopilotSpacesController < ApplicationController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include CopilotSpaces::HydroEventsHelper
  include CopilotSpaces::FeaturePreviewRedirect

  before_action :require_copilot_spaces_feature_enabled
  before_action :login_required
  before_action :parse_json_params, only: [:create, :update, :resource_sizes, :validate_url_resources]

  allow_verified_fetch only: [:create, :update, :destroy, :resource_sizes,  :validate_url_resources]

  rescue_from ActiveRecord::RecordNotFound, with: :render_404

  self.react_bundle_name = "custom-copilots"

  def create
    owner = get_owner(create_custom_copilot_params)
    copilot_space = CopilotSpace.new(create_custom_copilot_params)

    return render_404 unless owner
    copilot_space.owner = owner

    copilot_space.creator = current_user
    assign_user_and_cap(copilot_space)

    if copilot_space.save
      CopilotSpaces::HydroEventsHelper.instrument_hydro_events(:create, copilot_space, current_user, request, cap_filter)

      payload = CopilotSpaces::PageData::CopilotSpace::Payload.call(copilot_space).as_json

      render json: payload, status: :ok
    else
      # We need to set the uuid to nil here because the uuid is generated in the before_validation callback
      # This uuid would not exist in the database since the record was not saved.
      # Same for the number
      copilot_space.uuid = nil
      copilot_space.number = nil
      CopilotSpaces::HydroEventsHelper.instrument_hydro_events(:create, copilot_space, current_user, request, cap_filter)
      render json: { errorMessages: format_error_messages(copilot_space.errors) }, status: :unprocessable_entity
    end
  end

  def update
    return render_404 unless copilot_space.editable_by?(current_user)

    params_to_update = update_custom_copilot_params

    # Handle duplicate github file resources before assigning to the model
    if params_to_update[:resources_attributes].present?
      handle_duplicate_github_file_resources(params_to_update[:resources_attributes])
    end

    copilot_space.assign_attributes(params_to_update)
    assign_user_and_cap(copilot_space)

    if copilot_space.save
      CopilotSpaces::HydroEventsHelper.instrument_hydro_events(:update, copilot_space, current_user, request, cap_filter)
      payload = CopilotSpaces::PageData::CopilotSpace::Payload.call(copilot_space).as_json

      render json: payload, status: :ok
    else
      CopilotSpaces::HydroEventsHelper.instrument_hydro_events(:update, copilot_space, current_user, request, cap_filter)
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

    copilot_space.destroy!
    CopilotSpaces::HydroEventsHelper.instrument_hydro_events(:delete, copilot_space, current_user, request, cap_filter)
    head :ok
  end

  def validate_url_resources # rubocop:todo GitHub/UseRestfulActions
    resources = handle_url_resources(params[:resources_attributes])
    status = :ok

    valid_resources = []
    resource_errors = []
    owner = params[:space_owner].present? ? User.find_by_login(params[:space_owner]) : current_user

    resources.map do |resource|
      ccr = CopilotSpaceResource.new(resource_type: resource[:resource_type], metadata: resource[:metadata])
      ccr.copilot_space = CopilotSpace.new(current_user:, cap_filter:, owner: owner)
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

    render json: payload, status: status
  end

  def resource_sizes # rubocop:disable GitHub/UseRestfulActions
    # Calculating the size percentage of the resource requires the current user because we check a feature flag
    # to determine their max size on CopilotSpace.max_content_size
    #
    # So we need to create a CopilotSpace and set it on the resource so the resource has access to the current user
    copilot_space = CopilotSpace.new(current_user:, cap_filter:)

    repository_ids_from_params = resource_sizes_params.filter_map do |resource_params|
      resource_params[:metadata][:repository_id]
    end
    authorized_repos_indexed_by_id = copilot_space.authorized_repositories(repository_ids_from_params, viewer: current_user, cap_filter:).index_by(&:id)

    # Returns hash where the keys are the resource ids from the frontend, and the value is a float size percentage
    #
    #  {'id-from-frontend': 0.1249123}
    unsupported_files = []
    payload = resource_sizes_params.inject({}) do |payload, resource_params|
      resource = CopilotSpaceResource.new(resource_params.except(:_destroy))
      resource.copilot_space = copilot_space

      # check if the github file resource is serializable by twirp
      if resource.github_file_resource_type? && resource.twirp_resource.nil?
        file_path = resource["metadata"]["file_path"]
        unsupported_files << file_path
      end

      # Make sure resources that require access to a repo are authorized for this use
      if (
        !resource.free_text_resource_type? &&
        !resource.uploaded_text_file_resource_type? &&
        !resource.media_content_resource_type? &&
        !authorized_repos_indexed_by_id[resource.repository_id]
      )
        # If the current user cannot see this repository then return the payload without a size. That way we don't
        # reveal whether the repo exists or not. They only see the size of the file if the repo and file exist.
        payload
      else
        # This is id from the frontend. It is either the database id, or a id set on the front for unsaved resources
        id_from_frontend = resource_params[:id]
        payload[id_from_frontend] = resource.size_percentage
        payload
      end
    end

    if unsupported_files.any?
      return render json: { errorMessages: { base: "unsupported_file_type", files: unsupported_files } }, status: :unprocessable_entity
    end

    render json: payload, status: :ok
  end

  private

  # Filter out any github file resources that would be duplicates
  def handle_duplicate_github_file_resources(resources_attributes)
    return unless resources_attributes.present?

    # Only process new github file resources (those without IDs)
    new_github_file_resources = resources_attributes.select do |resource|
      resource[:id].blank? && resource[:resource_type] == "github_file"
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
      resource[:resource_type] == "github_issue" || resource[:resource_type] == "github_pull_request"
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
    if params[:number].present? && params[:owner].present?
      CopilotSpace.for_owner_login_and_number!(params[:owner], params[:number])
    else
      CopilotSpace.find_by!(id: params[:id])
    end
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

  def share_custom_copilot_params
    [
      :name,
      :description,
      :general_instructions,
      :icon_type,
      :icon_color,
      :visibility,
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
      :resource_type,
      { metadata:
        [
          :repository_id,
          :file_path,
          :text,
          :name,
          :number,
          :copilot_chat_attachment_id,
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
      .permit(*share_custom_copilot_params)

    # Preventing a hard error from being thrown by #permit
    unless user_feature_enabled?(:copilot_custom_copilots_visibility)
      permitted_params.delete(:visibility)
    end

    disallowed_resource_types = [].tap do |types|
      types << "github_issue" unless user_feature_enabled?(:custom_copilots_issues_prs)
      types << "github_pull_request" unless user_feature_enabled?(:custom_copilots_issues_prs)
      types << "media_content" unless user_feature_enabled?(:copilot_custom_copilots_images)
      types << "uploaded_text_file" unless user_feature_enabled?(:custom_copilots_file_uploads)
    end

    # If the user does not have a resource type enabled, remove the metadata and resource_type from the params. If resource contains an id, let it be as no action will occur
    if disallowed_resource_types.present? && permitted_params[:resources_attributes]
      permitted_params[:resources_attributes].each do |resource|
        if disallowed_resource_types.include?(resource[:resource_type])
          resource.delete(:metadata)
          resource.delete(:resource_type)
        end
      end
    end

    permitted_params
  end

  def create_custom_copilot_params
    permitted_params = [:owner_id, :owner_type] + share_custom_copilot_params

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
      types << "media_content" unless user_feature_enabled?(:copilot_custom_copilots_images)
      types << "uploaded_text_file" unless user_feature_enabled?(:custom_copilots_file_uploads)
    end

    # If the user does not have a resource type enabled, then those resources cannot be created or modified
    if disallowed_resource_types.present? && filtered_params[:resources_attributes]
      filtered_params[:resources_attributes].each do |resource|
        if disallowed_resource_types.include?(resource[:resource_type])
          resource.delete(:metadata)
          resource.delete(:resource_type)
        end
      end
    end

    filtered_params
  end

  def assign_user_and_cap(copilot_space)
    copilot_space.current_user = current_user
    copilot_space.cap_filter = cap_filter
  end

  def get_owner(params)
    return current_user unless user_feature_enabled?(:copilot_custom_copilots_org_owned) && params[:owner_type] && params[:owner_id]

    if params[:owner_type] ==  "Organization"
      return Organization.find_by!(id: params[:owner_id])
    end

    current_user
  end
end
