# typed: true
# frozen_string_literal: true

class Api::EnterpriseApiCustomImages < Api::Enterprise::App
  include Api::App::TwirpHelpers
  include Api::App::HostedRunnersHelper
  include ::Actions::LargerRunnersHelper
  include Actions::LargerRunners::CustomImagesHelper
  include ReceiveSchemaWithOpenApi

  ENTERPRISE_ACTIONS_CUSTOM_IMAGES_FORBIDDEN_MESSAGE = "Must have admin rights to Enterprise. Tokens must include the `manage_runners:enterprise` scope to use this endpoint"

  before "/enterprises/:enterprise_id/actions/hosted-runners/images/custom*" do
    enterprise = find_enterprise!
    deliver_error! 404 if GitHub.enterprise? # APIs are disabled for GHES
    deliver_error! 404, message: "Custom Images feature is disabled for the enterprise." unless is_custom_images_enabled?(entity: enterprise)
  end

  # List image definitions of a custom image in an enterprise
  get "/enterprises/:enterprise_id/actions/hosted-runners/images/custom", operation_id: "actions/list-custom-images-for-enterprise" do
    enterprise = find_enterprise!

    control_access :manage_enterprise_custom_images,
      resource: enterprise,
      forbid: true,
      forbid_message: ENTERPRISE_ACTIONS_CUSTOM_IMAGES_FORBIDDEN_MESSAGE,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    image_definitions = larger_runners_custom_images(enterprise)

    deliver :actions_runner_images_hash, { images: image_definitions }, status: 200
  end


  # Get an image version of a custom image in an enterprise
  get "/enterprises/:enterprise_id/actions/hosted-runners/images/custom/:image_definition_id", operation_id: "actions/get-custom-image-for-enterprise" do
    enterprise = find_enterprise!

    control_access :manage_enterprise_custom_images,
      resource: enterprise,
      forbid: true,
      forbid_message: ENTERPRISE_ACTIONS_CUSTOM_IMAGES_FORBIDDEN_MESSAGE,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    image_definition_id = int_id_param!(key: :image_definition_id, halt: true)

    image_definition = get_custom_image(entity: enterprise, image_id: image_definition_id)
    deliver :actions_runner_custom_images_hash, image_definition, status: 200
  end

  # List image versions of a custom image in an enterprise
  get "/enterprises/:enterprise_id/actions/hosted-runners/images/custom/:image_definition_id/versions", operation_id: "actions/list-custom-image-versions-for-enterprise" do
    enterprise = find_enterprise!
    version_pattern = params[:pattern] || nil

    control_access :manage_enterprise_custom_images,
      resource: enterprise,
      forbid: true,
      forbid_message: ENTERPRISE_ACTIONS_CUSTOM_IMAGES_FORBIDDEN_MESSAGE,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    image_definition_id = int_id_param!(key: :image_definition_id, halt: true)

    resp = handle_twirp_errors do
      if enterprise.feature_enabled?(:larger_runners_use_custom_images_from_ims)
        HostedComputeIms::Twirp.customer_images_client.list_customer_image_versions(
          owner: enterprise,
          image_definition_id: image_definition_id
        )
      else
        Launch::Twirp::larger_runners_client.list_image_versions(
          enterprise,
          image_definition_id: image_definition_id,
          pattern: version_pattern
        )
      end
    end

    image_versions = resp&.image_versions
    if enterprise.feature_enabled?(:larger_runners_use_custom_images_from_ims)
      image_versions = image_versions.select { |ver| check_image_version_pattern(ver.version, version_pattern) } if version_pattern
      deliver :actions_runner_ims_custom_image_versions_hash, { versions: image_versions }, status: 200
    else
      deliver :actions_runner_custom_image_versions_hash, { versions: image_versions }, status: 200
    end
  end

  # Get image version of a custom image in an enterprise
  get "/enterprises/:enterprise_id/actions/hosted-runners/images/custom/:image_definition_id/versions/:image_version", operation_id: "actions/get-custom-image-version-for-enterprise" do
    enterprise = find_enterprise!

    control_access :manage_enterprise_custom_images,
      resource: enterprise,
      forbid: true,
      forbid_message: ENTERPRISE_ACTIONS_CUSTOM_IMAGES_FORBIDDEN_MESSAGE,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    image_definition_id = int_id_param!(key: :image_definition_id, halt: true)

    resp = handle_twirp_errors do
      if enterprise.feature_enabled?(:larger_runners_use_custom_images_from_ims)
        HostedComputeIms::Twirp.customer_images_client.get_customer_image_version(
          owner: enterprise,
          image_definition_id: image_definition_id,
          version: params[:image_version]
        )
      else
        Launch::Twirp::larger_runners_client.get_image_version(
          enterprise,
          image_definition_id: image_definition_id,
          image_version: params[:image_version]
        )
      end
    end

    image_version = resp&.image_version
    if enterprise.feature_enabled?(:larger_runners_use_custom_images_from_ims)
      deliver :actions_runner_ims_custom_image_version_hash, image_version
    else
      deliver :actions_runner_custom_image_version_hash, image_version
    end
  end

  # Delete a custom image in an enterprise
  delete "/enterprises/:enterprise_id/actions/hosted-runners/images/custom/:image_definition_id", operation_id: "actions/delete-custom-image-from-enterprise" do
    enterprise = find_enterprise!

    control_access :manage_enterprise_custom_images,
      resource: enterprise,
      forbid: true,
      forbid_message: ENTERPRISE_ACTIONS_CUSTOM_IMAGES_FORBIDDEN_MESSAGE,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    image_definition_id = int_id_param!(key: :image_definition_id, halt: true)

    handle_twirp_errors do
      if enterprise.feature_enabled?(:larger_runners_use_custom_images_from_ims)
        HostedComputeIms::Twirp.customer_images_client.delete_customer_image_definition(
          owner: enterprise,
          image_definition_id: image_definition_id
        )
      else
        Launch::Twirp::larger_runners_client.delete_image_definition(
          enterprise,
          image_definition_id: image_definition_id
        )
      end
    end

    deliver_empty status: 204
  end

  # Delete a custom image version of an enterprise
  delete "/enterprises/:enterprise_id/actions/hosted-runners/images/custom/:image_definition_id/versions/:image_version", operation_id: "actions/delete-custom-image-version-from-enterprise" do
    enterprise = find_enterprise!

    control_access :manage_enterprise_custom_images,
      resource: enterprise,
      forbid: true,
      forbid_message: ENTERPRISE_ACTIONS_CUSTOM_IMAGES_FORBIDDEN_MESSAGE,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    image_definition_id = int_id_param!(key: :image_definition_id, halt: true)

    handle_twirp_errors do
      if enterprise.feature_enabled?(:larger_runners_use_custom_images_from_ims)
        HostedComputeIms::Twirp.customer_images_client.delete_customer_image_version(
          owner: enterprise,
          image_definition_id: image_definition_id,
          version: params[:image_version]
        )
      else
        Launch::Twirp::larger_runners_client.delete_image_version(
        enterprise,
        image_definition_id: image_definition_id,
        image_version: params[:image_version]
      )
      end
    end

    deliver_empty status: 204
  end
end
