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

  post "/internal/actions/hosted-runners/images/github-owned/:image_definition_id/versions", operation_id: "actions/create-curated-image-version-internal" do
    image_definition_id = params[:image_definition_id].to_i
    deliver_error! 400, message: "Invalid image_definition_id parameter" unless image_definition_id.present? && image_definition_id > 0

    data = receive_with_openapi
    deliver_error! 400, message: "Version is required" unless data["version"].present?
    deliver_error! 400, message: "Source VHD URL is required" unless data["source_vhd_url"].present?

    validate_vhd_url!(data["source_vhd_url"])

    resp = HostedComputeIms::Twirp.admin_client.create_curated_image_version(
      image_definition_id: image_definition_id,
      version: data["version"],
      source_vhd_url: data["source_vhd_url"],
      enabled: data["enabled"],
      vm_generation: HostedComputeIms::Utils.vm_generation_to_pb(data["vm_generation"]),
      os_state: HostedComputeIms::Utils.os_state_to_pb(data["os_state"]),
      agent_user: data["agent_user"],
      azure_purchase_plan: data["azure_purchase_plan"]
    )
    unless resp.call_succeeded?
      deliver_error!(resp.status, message: resp.options[:message])
    end

    image_version_raw = resp.value.image_version
    deliver_raw image_version_to_api_payload(image_version_raw), status: 201
  end

  get "/internal/actions/hosted-runners/images/github-owned/:image_definition_id/versions/:version", operation_id: "actions/get-curated-image-version-internal" do
    image_definition_id = params[:image_definition_id].to_i
    deliver_error! 400, message: "Invalid image_definition_id parameter" unless image_definition_id.present? && image_definition_id > 0

    version = params[:version]
    deliver_error! 400, message: "Invalid version parameter" unless version.present?

    resp = HostedComputeIms::Twirp.admin_client.get_curated_image_version(image_definition_id: image_definition_id.to_i, version: version)
    unless resp.call_succeeded?
      deliver_error!(resp.status, message: resp.options[:message])
    end

    image_version_raw = resp.value.image_version
    deliver_raw image_version_to_api_payload(image_version_raw)
  end

  patch "/internal/actions/hosted-runners/images/github-owned/:image_definition_id/versions/:version", operation_id: "actions/update-curated-image-version-internal" do
    image_definition_id = params[:image_definition_id].to_i
    deliver_error! 400, message: "Invalid image_definition_id parameter" unless image_definition_id.present? && image_definition_id > 0

    version = params[:version]
    deliver_error! 400, message: "Invalid version parameter" unless version.present?

    data = receive_with_openapi

    resp = HostedComputeIms::Twirp.admin_client.update_curated_image_version(
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

  get "/internal/actions/hosted-runners/images/github-owned/:image_definition_id", operation_id: "actions/get-curated-image-internal" do
    image_definition_id = params[:image_definition_id].to_i
    deliver_error! 400, message: "Invalid image_definition_id parameter" unless image_definition_id.present? && image_definition_id > 0

    resp = HostedComputeIms::Twirp.admin_client.get_curated_image_definition(image_definition_id: image_definition_id.to_i)
    unless resp.call_succeeded?
      deliver_error!(resp.status, message: resp.options[:message])
    end

    image_definition_raw = resp.value.image_definition
    deliver_raw image_definition_to_api_payload(image_definition_raw)
  end

  private

  def validate_vhd_url!(vhd_url)
    if vhd_url.present?
      return if vhd_url.start_with?("https://hostedimagestaging.blob.core.windows.net/") # storage account for curated images in AME tenant
      return if vhd_url.start_with?("https://ghrunnerimages.blob.core.windows.net/") # storage account for curated images in githubazure tenant
      return if vhd_url.start_with?("https://hostedcodespaceprebuild.blob.core.windows.net/") # storage account for codespace images in AME tenant
      return if vhd_url.start_with?("https://imstestimagesprem.blob.core.windows.net/") # storage account for dev images in githubazure tenant
      return if vhd_url.start_with?("os://")  # os:// format is used for macos images resource id
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
      created_on: data.created_at
    }
  end

  def image_definition_to_api_payload(data)
    {
      id: data.id,
      name: data.name,
      owner_id: data.owner_id,
      latest_version: data.latest_version
    }
  end
end
