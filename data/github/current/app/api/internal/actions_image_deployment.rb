# typed: true
# frozen_string_literal: true

# It is Internal API which intended for deploying a new image version for curated images on GitHub Actions
# Under hood, it calls IMS service to manage image versions
# This API is called from image deployment workflow and authentication is done via HMAC

class Api::Internal::ActionsImageDeployment < Api::Internal
  def externally_accessible?
    # API should be accessible from regular GitHub Hosted Runners which are hosted in Azure
    true
  end

  def require_request_hmac?
    # HMAC keys are stored in "GitHub.api_internal_actions_image_deployment_hmac_keys"
    # which reads "API_INTERNAL_ACTIONS_IMAGE_DEPLOYMENT_HMAC_KEYS" environment variable
    true
  end

  def authenticated_for_private_mode?
    true
  end

  post "/internal/actions/hosted-runners/images/github-owned/:image_definition_id/versions", operation_id: "actions/create-curated-image-version" do
    image_definition_id = params[:image_definition_id].to_i
    deliver_error! 400, message: "Invalid image_definition_id parameter" unless image_definition_id.present? && image_definition_id > 0

    data = receive_with_openapi
    deliver_error! 400, message: "Version is required" unless data["version"].present?
    deliver_error! 400, message: "Source VHD URL is required" unless data["source_vhd_url"].present?

    validate_vhd_url!(data["source_vhd_url"])

    resp = ims_admin_client.create_curated_image_version(
      image_definition_id: image_definition_id,
      version: data["version"],
      source_vhd_url: data["source_vhd_url"],
      enabled: data["enabled"]
    )
    unless resp.call_succeeded?
      deliver_error!(resp.status, message: resp.options[:message])
    end

    image_version_raw = resp.value.image_version
    deliver_raw image_version_to_api_payload(image_version_raw), status: 201
  end

  get "/internal/actions/hosted-runners/images/github-owned/:image_definition_id/versions/:version", operation_id: "actions/get-curated-image-version" do
    image_definition_id = params[:image_definition_id].to_i
    deliver_error! 400, message: "Invalid image_definition_id parameter" unless image_definition_id.present? && image_definition_id > 0

    version = params[:version]
    deliver_error! 400, message: "Invalid version parameter" unless version.present?

    resp = ims_admin_client.get_curated_image_version(image_definition_id: image_definition_id.to_i, version: version)
    unless resp.call_succeeded?
      deliver_error!(resp.status, message: resp.options[:message])
    end

    image_version_raw = resp.value.image_version
    deliver_raw image_version_to_api_payload(image_version_raw)
  end

  patch "/internal/actions/hosted-runners/images/github-owned/:image_definition_id/versions/:version", operation_id: "actions/update-curated-image-version" do
    image_definition_id = params[:image_definition_id].to_i
    deliver_error! 400, message: "Invalid image_definition_id parameter" unless image_definition_id.present? && image_definition_id > 0

    version = params[:version]
    deliver_error! 400, message: "Invalid version parameter" unless version.present?

    data = receive_with_openapi

    resp = ims_admin_client.update_curated_image_version(
      image_definition_id: image_definition_id,
      version: version,
      enabled: data["enabled"]
    )
    unless resp.call_succeeded?
      deliver_error!(resp.status, message: resp.options[:message])
    end

    image_version_raw = resp.value.image_version
    deliver_raw image_version_to_api_payload(image_version_raw)
  end

  private

  sig { returns(HostedComputeIms::Twirp::AdminClient) }
  def ims_admin_client
    HostedComputeIms::Twirp::AdminClient.new
  end

  def validate_vhd_url!(vhd_url)
    if vhd_url.present?
      return if vhd_url.start_with?("https://hostedimagestaging.blob.core.windows.net/")
      return if vhd_url.start_with?("https://hostedcodespaceprebuild.blob.core.windows.net/")
    end

    deliver_error! 400, message: "Forbidden vhd url source"
  end

  def image_version_to_api_payload(data)
    {
      image_definition_id: data.image_definition_id,
      version: data.version,
      state: data.state,
      state_details: data.state_details,
      size_gb: data.size_gb,
      enabled: data.enabled,
    }
  end
end
