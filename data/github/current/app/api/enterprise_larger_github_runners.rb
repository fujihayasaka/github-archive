# typed: true
# frozen_string_literal: true

class Api::EnterpriseLargerGitHubRunners < Api::App
  include Api::App::TwirpHelpers
  include Actions::LargerRunnersHelper
  include ReceiveSchemaWithOpenApi

  # Get pool information by pool ID
  get "/enterprises/:enterprise_id/actions/github-hosted-runners/:runner_id", operation_id: :internal do
    ent = find_enterprise!
    pool_id = int_id_param!(key: :runner_id, halt: true)

    control_access :read_enterprise_self_hosted_runners,
      resource: ent,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant_and_confirm_api_enabled!(ent)

    resp = handle_twirp_errors do
      Launch::Twirp::larger_runners_client.get_pool(
        ent,
        pool_id: pool_id
      )
    end

    pool = resp&.pool
    deliver :actions_runnerpool_hash, pool
  end

  # List image versions for image defintiion
  get "/enterprises/:enterprise_id/actions/github-hosted-runners/images/custom/:image_definition_id/versions", operation_id: :internal do
    ent = find_enterprise!

    control_access :read_enterprise_self_hosted_runners,
      resource: ent,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant_and_confirm_api_enabled!(ent)

    resp = handle_twirp_errors do
      Launch::Twirp::larger_runners_client.list_image_versions(
        ent,
        image_definition_id: int_id_param!(key: :image_definition_id, halt: true)
      )
    end

    image_versions = resp&.image_versions
    deliver :actions_runner_image_versions_hash, image_versions
  end

  # Get image version for image defintiion
  get "/enterprises/:enterprise_id/actions/github-hosted-runners/images/custom/:image_definition_id/versions/:image_version", operation_id: :internal do
    ent = find_enterprise!

    control_access :read_enterprise_self_hosted_runners,
      resource: ent,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant_and_confirm_api_enabled!(ent)

    resp = handle_twirp_errors do
      Launch::Twirp::larger_runners_client.get_image_version(
        ent,
        image_definition_id: int_id_param!(key: :image_definition_id, halt: true),
        image_version: params[:image_version]
      )
    end

    image_version = resp&.image_version
    deliver :actions_runner_image_version_hash, image_version
  end

  # Upload new image version for image defintiion
  post "/enterprises/:enterprise_id/actions/github-hosted-runners/images/custom/:image_definition_id/versions", operation_id: :internal do
    ent = find_enterprise!

    control_access :write_enterprise_self_hosted_runners,
      resource: ent,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant_and_confirm_api_enabled!(ent)

    data = receive(Hash)

    resp = handle_twirp_errors do
      Launch::Twirp::larger_runners_client.create_image_version(
        ent,
        image_definition_id: int_id_param!(key: :image_definition_id, halt: true),
        image_sas_uri: data["image_sas_uri"]
      )
    end

    image_version = resp&.image_version
    deliver :actions_runner_image_version_hash, image_version, status: 201
  end

  # Delete image version for image defintiion
  delete "/enterprises/:enterprise_id/actions/github-hosted-runners/images/custom/:image_definition_id/versions/:image_version", operation_id: :internal do
    ent = find_enterprise!

    control_access :write_enterprise_self_hosted_runners,
      resource: ent,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant_and_confirm_api_enabled!(ent)

    handle_twirp_errors do
      Launch::Twirp::larger_runners_client.delete_image_version(
        ent,
        image_definition_id: int_id_param!(key: :image_definition_id, halt: true),
        image_version: params[:image_version]
      )
    end

    deliver_empty status: 204
  end

  private

  def ensure_tenant_and_confirm_api_enabled!(enterprise)
    deliver_error! 404 unless GitHub.actions_larger_runners_enabled?

    unless enterprise.can_use_larger_runners?
      if enterprise.is_eligible_to_onboard_larger_runners?
        enterprise.onboard_larger_runners(actor: current_user)
      else
        deliver_error! 404
      end
    end

    handle_twirp_errors do
      Launch::Twirp.deployer_client.setup_tenant(enterprise)
    end
  end
end
