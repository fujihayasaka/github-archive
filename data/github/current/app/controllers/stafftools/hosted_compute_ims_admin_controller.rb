# typed: false
# frozen_string_literal: true

class Stafftools::HostedComputeImsAdminController < StafftoolsController
  include ApplicationController::VerifiedFetchDependency

  before_action :dotcom_required # limiting to dotcom so only GitHub staff can access
  before_action :ims_stafftools_enabled

  allow_verified_fetch only: [:index, :create_curated_pointer, :create_curated_image, :update_curated_image, :update_curated_pointer, :delete_curated_image, :delete_curated_pointer, :update_image_version, :delete_image_version, :image_reference]

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
    only: [:index, :show, :image_reference]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :image_reference],
    optional: true

  sig { returns(String) }
  def self.react_bundle_name
    "hosted-compute-ims-stafftools"
  end

  def index
    # IMS is a new service and we don't have real API calls to it.
    # This stafftools controller and UI is used for testing integration between dotcom and IMS
    # So, hardcode our test org "bbq-beets" for now because "current_user.organizations.first" seems to be too unpredictable
    current_org = Organization.find_by_login("bbq-beets")
    unless current_org.present?
      current_org = current_user.organizations.first
    end
    return redirect_to "/" unless current_org.present?

    image_definitions_error = nil
    image_versions_error = nil

    resp = ims_admin_client.list_curated_image_definitions

    image_definitions_raw = []

    if resp.call_succeeded
      image_definitions_raw = resp.value&.image_definitions || []
    else
      GitHub.logger.error({
        msg: "failed to fetch image definitions",
        fn: "hosted_compute_ims_admin.index",
        status: resp.status,
        exception: resp.options[:message] })
      return render_404
    end

    render_react_app(
      payload: {
        imageDefinitions: image_definitions_raw.map(&method(:convert_image_definition_to_react_payload)),
      },
      title: "Hosted Compute IMS",
      layout: "layouts/stafftools/react_stafftools",
    )
  end

  def create_curated_pointer # rubocop:todo GitHub/UseRestfulActions
    body = JSON.parse(request&.body.read)

    unless body["name"].present? && body["pointsToImageDefinitionId"].present? && body.key?("enabled")
      return render_validation_error(error: "Missing Parameters")
    end

    create_image_pointer_resp = ims_admin_client.create_curated_image_definition_pointer(
      name: body["name"],
      points_to_image_definition_id: body["pointsToImageDefinitionId"],
      enabled: body["enabled"],
      feature_flag: body["featureFlag"].to_s
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

    create_image_definition_resp = ims_admin_client.create_curated_image_definition(
      name: body["name"],
      os_type: body["osType"],
      architecture: body["architecture"],
      enabled: body["enabled"],
      feature_flag: body["featureFlag"].to_s
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

  def show
    id = params[:image_definition_id].to_i
    image_definition_resp = ims_admin_client.get_curated_image_definition(image_definition_id: id)

    image_definition = nil

    if image_definition_resp.call_succeeded?
      image_definition = image_definition_resp.value&.image_definition
    else
      GitHub.logger.error({
        msg: "failed to fetch image definition",
        fn: "hosted_compute_ims_admin.show",
        status: image_definition_resp.status,
        exception: image_definition_resp.options[:message] })
      return render_404
    end

    image_versions_resp = ims_admin_client.list_curated_image_versions(image_definition_id: id)

    image_versions = []
    if image_versions_resp.call_succeeded?
      image_versions = image_versions_resp.value&.image_versions || []
    else
      GitHub.logger.error({
        msg: "failed to fetch image versions",
        fn: "hosted_compute_ims_admin.show",
        status: image_versions_resp.status,
        exception: image_versions_resp.options[:message] })

      return render_404
    end

    latest_image_reference = nil
    image_reference_resp = ims_internal_client.get_image_reference(id: id, source: "Curated", version: "latest")
    if image_reference_resp.call_succeeded?
      latest_image_reference = image_reference_resp.value
    else
      GitHub.logger.error({
        msg: "failed to fetch latest image reference",
        fn: "hosted_compute_ims_admin.show",
        status: image_reference_resp.status,
        exception: image_reference_resp.options[:message] })
      latest_image_reference = nil
    end

    render_react_app(
      payload: {
        imageDefinition: convert_image_definition_to_react_payload(image_definition),
        imageVersions: image_versions.map(&method(:convert_image_version_to_react_payload)),
      },
      title: "Hosted Compute IMS",
      layout: "layouts/stafftools/react_stafftools",
    )
  end

  def update_curated_image # rubocop:todo GitHub/UseRestfulActions
    body = JSON.parse(request&.body.read)

    unless body["id"].present? && body["name"].present? && body.key?("enabled")
      return render_validation_error(error: "Missing Parameters")
    end

    update_curated_image_resp = ims_admin_client.update_curated_image_definition(
      image_definition_id: body["id"],
      name: body["name"],
      enabled: body["enabled"],
      feature_flag: body["featureFlag"].to_s
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

    update_curated_pointer_resp = ims_admin_client.update_curated_image_definition_pointer(
      image_definition_id: body["id"],
      name: body["name"],
      points_to_image_definition_id: body["pointsToImageDefinitionId"],
      enabled: body["enabled"],
      feature_flag: body["featureFlag"].to_s
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

    delete_curated_image_resp = ims_admin_client.delete_curated_image_definition(image_definition_id: body["id"])
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

    delete_curated_image_pointer_resp = ims_admin_client.delete_curated_image_definition_pointer(image_definition_id: body["id"])
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

  def update_image_version # rubocop:todo GitHub/UseRestfulActions
    body = JSON.parse(request&.body.read)
    unless body["id"].present? && body["version"].present? && body.key?("enabled")
      return render_validation_error(error: "Missing Parameters")
    end

    update_curated_image_version_resp = ims_admin_client.update_curated_image_version(
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

  def delete_image_version # rubocop:todo GitHub/UseRestfulActions
    body = JSON.parse(request&.body.read)

    unless body["id"].present? && body["version"].present?
      return render_validation_error(error: "Missing Parameters")
    end

    delete_curated_image_version_resp = ims_admin_client.delete_curated_image_version(
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

  def image_reference # rubocop:todo GitHub/UseRestfulActions
    image_definition_id = params[:image_definition_id].to_i
    version = params[:version].to_s

    image_reference_resp = ims_internal_client.get_image_reference(
      id: image_definition_id,
      source: "Curated",
      version: version
    )

    image_reference = image_reference_resp.value || nil
    if image_reference_resp.call_succeeded
      render json: {
        imageReference: convert_image_reference_to_react_payload(image_reference)
      }, status: :ok
    else
      GitHub.logger.error({
        msg: "failed to get image reference",
        fn: "hosted_compute_ims_admin.image_reference",
        status: image_reference_resp.status,
        exception: image_reference_resp.options[:message] })

      render json: {
        error: {
          code: image_reference_resp.status,
          message: image_reference_resp.options[:message],
        }
      }, status: :bad_request
    end
  end


  private

  memoize def ims_admin_client
    ::HostedComputeIms::Twirp::AdminClient.new
  end

  memoize def ims_internal_client
    ::HostedComputeIms::Twirp::InternalClient.new
  end

  def convert_image_definition_to_react_payload(object)
    image_versions_resp = ims_admin_client.list_curated_image_versions(image_definition_id: object.id)
    image_versions = image_versions_resp.value&.image_versions || []
    {
      id: object.id,
      name: object.name,
      osType: object.os_type,
      architecture: object.architecture,
      enabled: object.enabled,
      pointsToImageDefinitionId: object.points_to_image_definition_id,
      createdAt: object.created_at,
      updatedAt: object.updated_at,
      imageVersionsCount: image_versions.size,
      featureFlag: object.feature_flag.to_s
    }
  end

  def convert_image_version_to_react_payload(object)
    image_reference_resp = ims_internal_client.get_image_reference(id: object.image_definition_id, source: "Curated", version: "latest")
    exact_image_version = image_reference_resp.value&.exact_image_version || ""
    {
      id: object.id,
      imageDefinitionId: object.image_definition_id,
      version: object.version,
      state: object.state,
      stateDetails: object.state_details,
      sizeGb: object.size_gb,
      enabled: object.enabled,
      createdAt: object.created_at,
      updatedAt: object.created_at,
      isLatest: object.version == exact_image_version,
    }
  end

  def convert_image_reference_to_react_payload(object)
    {
      imageReference: object.image_reference.to_json,
      exactImageVersion: object.exact_image_version
    }
  end

  def render_validation_error(error:)
    render json: { error: error, error_category: "known" }, status: :unprocessable_entity
  end

  def ims_stafftools_enabled
    render_404 unless GitHub.flipper[:hosted_compute_ims_stafftools].enabled?(current_user)
  end
end
