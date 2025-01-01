# typed: true
# frozen_string_literal: true

class Stafftools::HostedComputeImsAdminController < StafftoolsController
  include ApplicationController::VerifiedFetchDependency

  before_action :dotcom_required # limiting to dotcom so only GitHub staff can access
  before_action :ims_stafftools_enabled

  allow_verified_fetch only: [:create_curated_pointer, :create_curated_image, :update_curated_image, :update_curated_pointer, :delete_curated_image, :delete_curated_pointer, :update_curated_image_version, :delete_curated_image_version]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    only: [:index, :curated_image_details, :curated_image_version_details]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :curated_image_details, :curated_image_version_details],
    optional: true

  sig { returns(String) }
  def self.react_bundle_name
    "hosted-compute-ims-stafftools"
  end

  def index
    selected_images_tab = params[:tab] || ""
    if selected_images_tab.present?
      unless %w(github-images partner-images pointers azuredevops-images).include?(selected_images_tab)
        return redirect_to stafftools_hosted_compute_ims_admin_index_path
      end
    end

    image_definitions = []
    image_definitions_resp = HostedComputeIms::Twirp.admin_client.list_curated_image_definitions
    if image_definitions_resp.call_succeeded
      image_definitions = image_definitions_resp.value&.image_definitions || []
    else
      GitHub.logger.error({
        msg: "failed to fetch image definitions",
        fn: "hosted_compute_ims_admin.index",
        status: image_definitions_resp.status,
        exception: image_definitions_resp.options[:message] })
      return render_404
    end

    payload = IndexRoutePayload.new(
      image_definitions: image_definitions.map(&method(:convert_image_definition_to_react_payload)),
      selected_images_tab: selected_images_tab
    )
    respond_with_react(
      payload: payload,
      title: "Hosted Compute IMS",
      layout: "layouts/stafftools/react_stafftools"
    )
  end

  def curated_image_details # rubocop:todo GitHub/UseRestfulActions
    image_definition_id = params[:image_definition_id].to_i

    get_image_definition_resp = HostedComputeIms::Twirp.admin_client.get_curated_image_definition(image_definition_id: image_definition_id)
    unless get_image_definition_resp.call_succeeded?
      GitHub.logger.error({
        msg: "failed to fetch image definition",
        fn: "hosted_compute_ims_admin.curated_image_details",
        status: get_image_definition_resp.status,
        exception: get_image_definition_resp.options[:message] })
      return render_404
    end

    image_definition = get_image_definition_resp.value&.image_definition
    image_versions = []
    referenced_image_definition = nil

    if image_definition.points_to_image_definition_id.to_i == 0
      # List image versions only if image definition is not a pointer because pointer can't have image versions
      list_image_versions_resp = HostedComputeIms::Twirp.admin_client.list_curated_image_versions(image_definition_id: image_definition_id)
      if list_image_versions_resp.call_succeeded?
        image_versions = list_image_versions_resp.value&.image_versions || []
      else
        GitHub.logger.error({
          msg: "failed to fetch image versions",
          fn: "hosted_compute_ims_admin.curated_image_details",
          status: list_image_versions_resp.status,
          exception: list_image_versions_resp.options[:message] })
        return render_404
      end
    else
      # If image definition is pointer, get referenced image definition too
      referenced_image_definition_resp = HostedComputeIms::Twirp.admin_client.get_curated_image_definition(image_definition_id: image_definition.points_to_image_definition_id)
      if referenced_image_definition_resp.call_succeeded?
        referenced_image_definition = referenced_image_definition_resp.value&.image_definition
      end
    end

    payload = ImageDetailsRoutePayload.new(
      image_definition: convert_image_definition_to_react_payload(image_definition),
      referenced_image_definition: referenced_image_definition.present? ? convert_image_definition_to_react_payload(referenced_image_definition) : nil,
      image_versions: image_versions.map(&method(:convert_image_version_to_react_payload))
    )
    respond_with_react(
      payload: payload,
      title: "Hosted Compute IMS",
      layout: "layouts/stafftools/react_stafftools"
    )
  end

  def curated_image_version_details # rubocop:todo GitHub/UseRestfulActions
    image_definition_id = params[:image_definition_id].to_i
    version = params[:version].to_s

    get_image_definition_resp = HostedComputeIms::Twirp.admin_client.get_curated_image_definition(image_definition_id: image_definition_id)
    unless get_image_definition_resp.call_succeeded?
      GitHub.logger.error({
        msg: "failed to fetch image definition",
        fn: "hosted_compute_ims_admin.curated_image_version_details",
        status: get_image_definition_resp.status,
        exception: get_image_definition_resp.options[:message] })
      return render_404
    end

    image_definition = get_image_definition_resp.value&.image_definition
    if image_definition.points_to_image_definition_id.to_i > 0
      return redirect_to stafftools_hosted_compute_ims_admin_curated_image_details_path(image_definition_id: image_definition_id)
    end

    if version == "latest"
      exact_version = image_definition.latest_version
    else
      exact_version = version
    end

    get_image_version_resp = HostedComputeIms::Twirp.admin_client.get_curated_image_version(image_definition_id: image_definition_id, version: exact_version)
    unless get_image_version_resp.call_succeeded?
      GitHub.logger.error({
        msg: "failed to fetch image version",
        fn: "hosted_compute_ims_admin.curated_image_version_details",
        status: get_image_version_resp.status,
        exception: get_image_version_resp.options[:message] })
      return render_404
    end

    image_version = get_image_version_resp.value&.image_version

    payload = ImageVersionDetailsRoutePayload.new(
      image_definition: convert_image_definition_to_react_payload(image_definition),
      image_version: convert_image_version_to_react_payload(image_version)
    )
    respond_with_react(
      payload: payload,
      title: "Hosted Compute IMS",
      layout: "layouts/stafftools/react_stafftools"
    )
  end

  def create_curated_pointer # rubocop:todo GitHub/UseRestfulActions
    body = JSON.parse(request&.body.read)

    unless body["name"].present? && body["pointsToImageDefinitionId"].present? && body.key?("enabled")
      return render_validation_error(error: "Missing Parameters")
    end

    create_image_pointer_resp = HostedComputeIms::Twirp.admin_client.create_curated_image_definition_pointer(
      name: body["name"],
      owner_id: body["ownerId"],
      points_to_image_definition_id: body["pointsToImageDefinitionId"],
      enabled: body["enabled"],
      feature_flag: body["featureFlag"].to_s,
      is_image_generation_supported: body["isImageGenerationSupported"]
    )

    if create_image_pointer_resp.call_succeeded
      render json: {}, status: :ok
    else
      GitHub.logger.error({
        msg: "failed to create image definition pointer",
        fn: "hosted_compute_ims_admin.create_curated_pointer",
        status: create_image_pointer_resp.status,
        exception: create_image_pointer_resp.options[:message] })

      render json: {
        error: {
          code: create_image_pointer_resp.status,
          message: create_image_pointer_resp.options[:message],
        }
      }, status: :bad_request
    end
  end

  def create_curated_image # rubocop:todo GitHub/UseRestfulActions
    current_org = Organization.find_by_login("bbq-beets")
    unless current_org.present?
      current_org = current_user.organizations.first
    end

    body = JSON.parse(request&.body.read)

    unless body["name"].present? && body["osType"].present? && body["architecture"].present? && body.key?("enabled")
      return render_validation_error(error: "Missing Parameters")
    end

    create_image_definition_resp = HostedComputeIms::Twirp.admin_client.create_curated_image_definition(
      name: body["name"],
      owner_id: body["ownerId"],
      os_type: body["osType"],
      architecture: body["architecture"],
      enabled: body["enabled"],
      feature_flag: body["featureFlag"].to_s,
      is_image_generation_supported: body["isImageGenerationSupported"]
    )

    if create_image_definition_resp.call_succeeded
      render json: {}, status: :ok
    else
      GitHub.logger.error({
        msg: "failed to create image definition",
        fn: "hosted_compute_ims_admin.create_curated_image",
        status: create_image_definition_resp.status,
        exception: create_image_definition_resp.options[:message] })

      render json: {
        error: {
          code: create_image_definition_resp.status,
          message: create_image_definition_resp.options[:message],
        }
      }, status: :bad_request
    end
  end

  def update_curated_image # rubocop:todo GitHub/UseRestfulActions
    body = JSON.parse(request&.body.read)

    unless body["id"].present? && body["name"].present? && body.key?("enabled")
      return render_validation_error(error: "Missing Parameters")
    end

    update_curated_image_resp = HostedComputeIms::Twirp.admin_client.update_curated_image_definition(
      image_definition_id: body["id"],
      name: body["name"],
      enabled: body["enabled"],
      feature_flag: body["featureFlag"].to_s,
      is_image_generation_supported: body["isImageGenerationSupported"]
    )

    if update_curated_image_resp.call_succeeded
      render json: {}, status: :ok
    else
      GitHub.logger.error({
        msg: "failed to update image definition",
        fn: "hosted_compute_ims_admin.update_curated_image",
        status: update_curated_image_resp.status,
        exception: update_curated_image_resp.options[:message] })

      render json: {
        error: {
          code: update_curated_image_resp.status,
          message: update_curated_image_resp.options[:message],
        }
      }, status: :bad_request
    end
  end

  def update_curated_pointer # rubocop:todo GitHub/UseRestfulActions
    body = JSON.parse(request&.body.read)

    unless body["id"].present? && body["name"].present? && body["pointsToImageDefinitionId"].present? && body.key?("enabled")
      return render_validation_error(error: "Missing Parameters")
    end

    update_curated_pointer_resp = HostedComputeIms::Twirp.admin_client.update_curated_image_definition_pointer(
      image_definition_id: body["id"],
      name: body["name"],
      points_to_image_definition_id: body["pointsToImageDefinitionId"],
      enabled: body["enabled"],
      feature_flag: body["featureFlag"].to_s,
      is_image_generation_supported: body["isImageGenerationSupported"]
    )
    if update_curated_pointer_resp.call_succeeded
      render json: {}, status: :ok
    else
      GitHub.logger.error({
        msg: "failed to update image definition pointer",
        fn: "hosted_compute_ims_admin.update_curated_pointer",
        status: update_curated_pointer_resp.status,
        exception: update_curated_pointer_resp.options[:message] })

      render json: {
        error: {
          code: update_curated_pointer_resp.status,
          message: update_curated_pointer_resp.options[:message],
        }
      }, status: :bad_request
    end
  end

  def delete_curated_image # rubocop:todo GitHub/UseRestfulActions
    body = JSON.parse(request&.body.read)

    unless body["id"].present?
      return render_validation_error(error: "Missing Parameters")
    end

    delete_curated_image_resp = HostedComputeIms::Twirp.admin_client.delete_curated_image_definition(image_definition_id: body["id"])
    if delete_curated_image_resp.call_succeeded
      render json: {}, status: :ok
    else
      GitHub.logger.error({
        msg: "failed to delete image definition",
        fn: "hosted_compute_ims_admin.delete_curated_image",
        status: delete_curated_image_resp.status,
        exception: delete_curated_image_resp.options[:message] })

      render json: {
        error: {
          code: delete_curated_image_resp.status,
          message: delete_curated_image_resp.options[:message],
        }
      }, status: :bad_request
    end
  end

  def delete_curated_pointer # rubocop:todo GitHub/UseRestfulActions
    body = JSON.parse(request&.body.read)

    unless body["id"].present?
      return render_validation_error(error: "Missing Parameters")
    end

    delete_curated_image_pointer_resp = HostedComputeIms::Twirp.admin_client.delete_curated_image_definition_pointer(image_definition_id: body["id"])
    if delete_curated_image_pointer_resp.call_succeeded
      render json: {}, status: :ok
    else
      GitHub.logger.error({
        msg: "failed to delete image definition pointer",
        fn: "hosted_compute_ims_admin.delete_curated_pointer",

        status: delete_curated_image_pointer_resp.status,
        exception: delete_curated_image_pointer_resp.options[:message] })

      render json: {
        error: {
          code: delete_curated_image_pointer_resp.status,
          message: delete_curated_image_pointer_resp.options[:message],
        }
      }, status: :bad_request
    end
  end

  def update_curated_image_version # rubocop:todo GitHub/UseRestfulActions
    body = JSON.parse(request&.body.read)
    unless body["id"].present? && body["version"].present? && body.key?("enabled")
      return render_validation_error(error: "Missing Parameters")
    end

    update_curated_image_version_resp = HostedComputeIms::Twirp.admin_client.update_curated_image_version(
      image_definition_id: body["id"],
      version: body["version"],
      enabled: body["enabled"]
    )

    if update_curated_image_version_resp.call_succeeded
      render json: {}, status: :ok
    else
      GitHub.logger.error({
        msg: "failed to update image version",
        fn: "hosted_compute_ims_admin.update_image_version",
        status: update_curated_image_version_resp.status,
        exception: update_curated_image_version_resp.options[:message] })

      render json: {
        error: {
          code: update_curated_image_version_resp.status,
          message: update_curated_image_version_resp.options[:message],
        }
      }, status: :bad_request
    end
  end

  def delete_curated_image_version # rubocop:todo GitHub/UseRestfulActions
    body = JSON.parse(request&.body.read)

    unless body["id"].present? && body["version"].present?
      return render_validation_error(error: "Missing Parameters")
    end

    delete_curated_image_version_resp = HostedComputeIms::Twirp.admin_client.delete_curated_image_version(
      image_definition_id: body["id"],
      version: body["version"]
    )

    if delete_curated_image_version_resp.call_succeeded
      render json: {}, status: :ok
    else
      GitHub.logger.error({
        msg: "failed to delete image version",
        fn: "hosted_compute_ims_admin.delete_image_version",
        status: delete_curated_image_version_resp.status,
        exception: delete_curated_image_version_resp.options[:message] })

      render json: {
        error: {
          code: delete_curated_image_version_resp.status,
          message: delete_curated_image_version_resp.options[:message],
        }
      }, status: :bad_request
    end
  end

  private

  class IndexRoutePayload < ReactPayload::Base
    def route_id
      "hostedComputeImsAdminRoute"
    end

    def initialize(**kwargs)
      kwargs.each do |k, v|
        instance_variable_set("@#{k}", v)
      end
    end

    def payload
      {
        imageDefinitions: @image_definitions,
        selectedImagesTab: @selected_images_tab,
      }
    end
  end

  class ImageDetailsRoutePayload < ReactPayload::Base
    def route_id
      "hostedComputeImageDetailsRoute"
    end

    def initialize(**kwargs)
      kwargs.each do |k, v|
        instance_variable_set("@#{k}", v)
      end
    end

    def payload
      {
        imageDefinition: @image_definition,
        referencedImageDefinition: @referenced_image_definition,
        imageVersions: @image_versions,
      }
    end
  end

  class ImageVersionDetailsRoutePayload < ReactPayload::Base
    def route_id
      "hostedComputeImageVersionDetailsRoute"
    end

    def initialize(**kwargs)
      kwargs.each do |k, v|
        instance_variable_set("@#{k}", v)
      end
    end

    def payload
      {
        imageDefinition: @image_definition,
        imageVersion: @image_version,
      }
    end
  end

  def convert_image_definition_to_react_payload(object)
    {
      id: object.id,
      name: object.name,
      ownerId: object.owner_id,
      osType: object.os_type,
      architecture: object.architecture,
      enabled: object.enabled,
      pointsToImageDefinitionId: object.points_to_image_definition_id,
      createdAt: object.created_at,
      updatedAt: object.updated_at,
      featureFlag: object.feature_flag.to_s,
      imageVersionsCount: object.image_versions_count,
      latestVersion: object.latest_version,
      isImageGenerationSupported: object.is_image_generation_supported,
    }
  end

  def convert_image_version_to_react_payload(object)
    {
      id: object.id,
      imageDefinitionId: object.image_definition_id,
      version: object.version,
      state: object.state,
      stateDetails: object.state_details,
      sizeGb: object.size_gb,
      enabled: object.enabled,
      createdAt: object.created_at,
      updatedAt: object.updated_at,
      resourceId: object.resource_id,
      vmGeneration: object.vm_generation,
      osState: object.os_state,
      azurePurchasePlan: object.azure_purchase_plan,
      agentUser: object.agent_user,
    }
  end

  def render_validation_error(error:)
    render json: { error: error, error_category: "known" }, status: :unprocessable_entity
  end

  def ims_stafftools_enabled
    render_404 unless FeatureFlag.vexi.enabled?(:hosted_compute_ims_stafftools, current_user, default: false)
  end


end
