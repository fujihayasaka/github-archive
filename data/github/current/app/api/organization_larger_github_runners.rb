# typed: true
# frozen_string_literal: true

class Api::OrganizationLargerGitHubRunners < Api::App
  include Api::App::TwirpHelpers
  include Actions::LargerRunnersHelper
  include ReceiveSchemaWithOpenApi

  # Get pool information by pool ID
  get "/organizations/:organization_id/actions/github-hosted-runners/:runner_id", operation_id: :internal do
    org = find_org!

    control_access :read_org_larger_runners,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant_and_confirm_api_enabled!(org)

    resp = handle_twirp_errors do
      Launch::Twirp::larger_runners_client.get_pool(
        org,
        pool_id: int_id_param!(key: :runner_id, halt: true)
      )
    end

    pool = resp&.pool
    deliver :actions_runnerpool_hash, pool
  end

  # List image versions for pool
  get "/organizations/:organization_id/actions/github-hosted-runners/images/custom/:image_definition_id/versions", operation_id: :internal do
    org = find_org!

    control_access :read_org_larger_runners,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant_and_confirm_api_enabled!(org)

    resp = handle_twirp_errors do
      if GitHub.flipper[:larger_runners_use_custom_images_from_ims].enabled?(org)
        ims_customer_images_client.list_customer_image_versions(
          owner: org,
          image_definition_id: int_id_param!(key: :image_definition_id, halt: true)
        )
      else
        Launch::Twirp::larger_runners_client.list_image_versions(
          org,
          image_definition_id: int_id_param!(key: :image_definition_id, halt: true)
        )
      end
    end

    image_versions = resp&.image_versions

    if GitHub.flipper[:larger_runners_use_custom_images_from_ims].enabled?(org)
      deliver :actions_runner_ims_custom_image_versions_hash, { versions: image_versions }, status: 200
    else
      deliver :actions_runner_custom_image_versions_hash, { versions: image_versions }, status: 200
    end
  end

  # Get image version for pool
  get "/organizations/:organization_id/actions/github-hosted-runners/images/custom/:image_definition_id/versions/:image_version", operation_id: :internal do
    org = find_org!

    control_access :read_org_larger_runners,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant_and_confirm_api_enabled!(org)

    resp = handle_twirp_errors do
      if GitHub.flipper[:larger_runners_use_custom_images_from_ims].enabled?(org)
        ims_customer_images_client.get_customer_image_version(
          owner: org,
          image_definition_id: int_id_param!(key: :image_definition_id, halt: true),
          version: params[:image_version]
        )
      else
        Launch::Twirp::larger_runners_client.get_image_version(
          org,
          image_definition_id: int_id_param!(key: :image_definition_id, halt: true),
          image_version: params[:image_version]
        )
      end
    end

    image_version = resp&.image_version
    if GitHub.flipper[:larger_runners_use_custom_images_from_ims].enabled?(org)
      deliver :actions_runner_ims_custom_image_version_hash, image_version
    else
      deliver :actions_runner_custom_image_version_hash, image_version
    end
  end

  # Upload new image version for pool
  post "/organizations/:organization_id/actions/github-hosted-runners/images/custom/:image_definition_id/versions", operation_id: :internal do
    org = find_org!

    control_access :write_org_larger_runners,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant_and_confirm_api_enabled!(org)

    data = receive(Hash)

    resp = handle_twirp_errors do
      if GitHub.flipper[:larger_runners_use_custom_images_from_ims].enabled?(org)
        ims_customer_images_client.create_customer_image_version(
        owner: org,
        image_definition_id: int_id_param!(key: :image_definition_id, halt: true),
        version: "",
        source_vhd_url: data["image_sas_uri"]
      )
      else
        Launch::Twirp::larger_runners_client.create_image_version(
        org,
        image_definition_id: int_id_param!(key: :image_definition_id, halt: true),
        image_sas_uri: data["image_sas_uri"]
      )
      end
    end

    image_version = resp&.image_version
    if GitHub.flipper[:larger_runners_use_custom_images_from_ims].enabled?(org)
      deliver :actions_runner_ims_custom_image_version_hash, image_version, status: 201
    else
      deliver :actions_runner_custom_image_version_hash, image_version, status: 201
    end
  end

  # Delete image version for pool
  delete "/organizations/:organization_id/actions/github-hosted-runners/images/custom/:image_definition_id/versions/:image_version", operation_id: :internal do
    org = find_org!

    control_access :write_org_larger_runners,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant_and_confirm_api_enabled!(org)

    handle_twirp_errors do
      if GitHub.flipper[:larger_runners_use_custom_images_from_ims].enabled?(org)
        ims_customer_images_client.delete_image_version(
          owner: org,
          image_definition_id: int_id_param!(key: :image_definition_id, halt: true),
          version: params[:image_version]
        )
      else
        Launch::Twirp::larger_runners_client.delete_image_version(
          org,
          image_definition_id: int_id_param!(key: :image_definition_id, halt: true),
          image_version: params[:image_version]
        )
      end
    end

    deliver_empty status: 204
  end

  private

  def ensure_tenant_and_confirm_api_enabled!(org)
    deliver_error! 404 unless GitHub.actions_larger_runners_enabled?

    unless org.can_use_larger_runners?
      if org.is_eligible_to_onboard_larger_runners?
        org.onboard_larger_runners(actor: current_user)
      else
        deliver_error! 404
      end
    end

    if org.business
      handle_twirp_errors do
        Launch::Twirp.deployer_client.setup_tenant(org.business)
      end
    end

    handle_twirp_errors do
      Launch::Twirp.deployer_client.setup_tenant(org)
    end
  end

  def ims_customer_images_client
    ::HostedComputeIms::Twirp::CustomerImagesClient.new
  end
end
