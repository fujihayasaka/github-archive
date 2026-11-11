# typed: true
# frozen_string_literal: true

class Api::OrganizationApiCustomImages < Api::App
  include Api::App::TwirpHelpers
  include Actions::LargerRunnersHelper
  include Actions::LargerRunners::CustomImagesHelper
  include Api::App::HostedRunnersHelper
  include ReceiveSchemaWithOpenApi

  before "/organizations/:organization_id/actions/hosted-runners/images/custom*" do
    org = find_org!
    deliver_error! 404 if GitHub.enterprise? # APIs are disabled for GHAE
    deliver_error! 404, message: "Custom Images feature is disabled for the org." unless is_custom_images_enabled?(entity: org)
  end

  # List custom images in an organization
  get "/organizations/:organization_id/actions/hosted-runners/images/custom", operation_id: "actions/list-custom-images-for-org" do
    org = find_org!

    control_access :read_org_custom_images,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_CUSTOM_IMAGES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    image_definitions = larger_runners_custom_images(org)

    deliver :actions_runner_images_hash, { images: image_definitions }, status: 200
  end

  # Get image versions of a custom image in an organization
  get "/organizations/:organization_id/actions/hosted-runners/images/custom/:image_definition_id", operation_id: "actions/get-custom-image-for-org" do
    org = find_org!

    control_access :read_org_custom_images,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_CUSTOM_IMAGES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    image_definition_id = int_id_param!(key: :image_definition_id, halt: true)

    image_definition = get_custom_image(entity: org, image_id: image_definition_id)
    deliver :actions_runner_custom_images_hash, image_definition, status: 200
  end

  # List image versions of a custom image in an organization
  get "/organizations/:organization_id/actions/hosted-runners/images/custom/:image_definition_id/versions", operation_id: "actions/list-custom-image-versions-for-org" do
    org = find_org!
    version_pattern = params[:pattern] || nil

    control_access :read_org_custom_images,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_CUSTOM_IMAGES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    image_definition_id = int_id_param!(key: :image_definition_id, halt: true)

    resp = handle_twirp_errors do
      if org.feature_flag_enabled?(:larger_runners_use_custom_images_from_ims, default: false)
        HostedComputeIms::Twirp.customer_images_client.list_customer_image_versions(
          owner: org,
          image_definition_id: image_definition_id
        )
      else
        Launch::Twirp::larger_runners_client.list_image_versions(
          org,
          image_definition_id: image_definition_id,
          pattern: version_pattern
        )
      end
    end
    image_versions = resp&.image_versions
    if org.feature_flag_enabled?(:larger_runners_use_custom_images_from_ims, default: false)
      image_versions = image_versions.select { |ver| check_image_version_pattern(ver.version, version_pattern) } if version_pattern
      deliver :actions_runner_ims_custom_image_versions_hash, { versions: image_versions }, status: 200
    else
      deliver :actions_runner_custom_image_versions_hash, { versions: image_versions }, status: 200
    end
  end

  # Get image version of a custom image in an organization
  get "/organizations/:organization_id/actions/hosted-runners/images/custom/:image_definition_id/versions/:image_version", operation_id: "actions/get-custom-image-version-for-org" do
    org = find_org!

    control_access :read_org_custom_images,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_CUSTOM_IMAGES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    image_definition_id = int_id_param!(key: :image_definition_id, halt: true)

    validate_semver_format!(params[:image_version])

    resp = handle_twirp_errors do
      if org.feature_flag_enabled?(:larger_runners_use_custom_images_from_ims, default: false)
        HostedComputeIms::Twirp.customer_images_client.get_customer_image_version(
          owner: org,
          image_definition_id: image_definition_id,
          version: params[:image_version]
        )
      else
        Launch::Twirp::larger_runners_client.get_image_version(
          org,
          image_definition_id: image_definition_id,
          image_version: params[:image_version]
        )
      end
    end

    image_version = resp&.image_version
    if org.feature_flag_enabled?(:larger_runners_use_custom_images_from_ims, default: false)
      deliver :actions_runner_ims_custom_image_version_hash, image_version
    else
      deliver :actions_runner_custom_image_version_hash, image_version
    end
  end

  # Delete a custom image in an organization
  delete "/organizations/:organization_id/actions/hosted-runners/images/custom/:image_definition_id", operation_id: "actions/delete-custom-image-from-org" do
    org = find_org!

    control_access :write_org_custom_images,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_CUSTOM_IMAGES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    image_definition_id = int_id_param!(key: :image_definition_id, halt: true)

    if is_custom_image_usage_by_runner_validation_enabled?(entity: org)
      if custom_image_in_use_by_runner?(org, image_definition_id)
        deliver_error! 422, message: "Failed to delete custom image because it's currently used by at least one runner."
      end
    end

    handle_twirp_errors do
      if org.feature_flag_enabled?(:larger_runners_use_custom_images_from_ims, default: false)
        HostedComputeIms::Twirp.customer_images_client.delete_customer_image_definition(
          owner: org,
          image_definition_id: image_definition_id
        )
      else
        Launch::Twirp::larger_runners_client.delete_image_definition(
          org,
          image_definition_id: image_definition_id
        )
      end
    end

    deliver_empty status: 204
  end

  # Delete a custom image version of an organization
  delete "/organizations/:organization_id/actions/hosted-runners/images/custom/:image_definition_id/versions/:image_version", operation_id: "actions/delete-custom-image-version-from-org" do
    org = find_org!

    control_access :write_org_custom_images,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_CUSTOM_IMAGES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    image_definition_id = int_id_param!(key: :image_definition_id, halt: true)

    validate_semver_format!(params[:image_version])

    if is_custom_image_usage_by_runner_validation_enabled?(entity: org)
      if custom_image_in_use_by_runner?(org, image_definition_id, params[:image_version])
        deliver_error! 422, message: "Failed to delete custom image version because it's currently used by at least one runner."
      end
    end

    handle_twirp_errors do
      if org.feature_flag_enabled?(:larger_runners_use_custom_images_from_ims, default: false)
        HostedComputeIms::Twirp.customer_images_client.delete_customer_image_version(
          owner: org,
          image_definition_id: image_definition_id,
          version: params[:image_version]
        )
      else
        Launch::Twirp::larger_runners_client.delete_image_version(
          org,
          image_definition_id: image_definition_id,
          image_version: params[:image_version]
        )
      end
    end

    deliver_empty status: 204
  end
end
