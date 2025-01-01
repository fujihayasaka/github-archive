# typed: true
# frozen_string_literal: true

class Api::EnterpriseHostedRunners < Api::Enterprise::App
  include Api::App::TwirpHelpers
  include Api::App::HostedRunnersHelper
  include ::Actions::LargerRunnersHelper
  include ReceiveSchemaWithOpenApi

  # Get Enterprise hosted runner list
  get "/enterprises/:enterprise_id/actions/hosted-runners", operation_id: "actions/list-hosted-runners-for-enterprise" do
    enterprise = find_enterprise!
    confirm_api_enabled!(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_larger_runners_and_launch_ready!(entity: enterprise, actor: current_user)

    resp = handle_twirp_errors do
      Launch::Twirp::larger_runners_client.list_pools(enterprise, entity: enterprise)
    end

    validate_listing!(resp&.pools)

    # We map to an Array so pagination works
    pools = paginate_rel(resp&.pools.map { |runner| runner })

    # Load all images for the enterprise
    image_sources = pools.map { |p| p.image.source }.uniq
    images = []
    images = images.chain(Actions::Image.curated_images_for(enterprise)) if image_sources.include?(:Curated)
    images = images.chain(Actions::Image.marketplace_images_for(enterprise)) if image_sources.include?(:Marketplace)
    images = images.chain(Actions::Image.custom_images_for(enterprise)) if image_sources.include?(:Custom) && is_custom_images_enabled?(entity: enterprise)

    deliver :larger_runners_hash, { pools: pools, images: images, custom_image_generation_feature_enabled: is_custom_image_generation_enabled?(entity: enterprise) }
  end

  # Get Enterprise hosted runner limits
  get "/enterprises/:enterprise_id/actions/hosted-runners/limits", operation_id: "actions/get-hosted-runners-limits-for-enterprise" do
    enterprise = find_enterprise!
    confirm_api_enabled!(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_larger_runners_and_launch_ready!(entity: enterprise, actor: current_user)

    data = {
      public_ips: {
        current_usage: Actions::LargerRunner.larger_runners_for(entity: enterprise, is_public_ip_enabled: true).count,
        maximum: public_ip_usage_limit_for(enterprise)
      }
    }

    deliver :larger_runner_limits_hash, data
  end

  # Get Enterprise hosted runner machine specs
  get "/enterprises/:enterprise_id/actions/hosted-runners/machine-sizes", operation_id: "actions/get-hosted-runners-machine-specs-for-enterprise" do
    enterprise = find_enterprise!
    confirm_api_enabled!(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_larger_runners_and_launch_ready!(entity: enterprise, actor: current_user)

    resp = handle_twirp_errors do
      Launch::Twirp::larger_runners_client.list_machine_specs(enterprise)
    end

    machine_specs = resp&.machineSpecs
    deliver :larger_runners_machine_specs_hash, machine_specs
  end

  # Get Enterprise hosted runner GitHub-owned images
  get "/enterprises/:enterprise_id/actions/hosted-runners/images/github-owned", operation_id: "actions/get-hosted-runners-github-owned-images-for-enterprise" do
    enterprise = find_enterprise!
    confirm_api_enabled!(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_larger_runners_and_launch_ready!(entity: enterprise, actor: current_user)

    deliver :actions_runner_curated_images_hash, { images: Actions::Image.curated_images_for(enterprise) }
  end

  # Get Enterprise hosted runner partner images
  get "/enterprises/:enterprise_id/actions/hosted-runners/images/partner", operation_id: "actions/get-hosted-runners-partner-images-for-enterprise" do
    enterprise = find_enterprise!
    confirm_api_enabled!(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_larger_runners_and_launch_ready!(entity: enterprise, actor: current_user)

    deliver :actions_runner_curated_images_hash, { images: Actions::Image.marketplace_images_for(enterprise) }
  end

  # Get Enterprise larger runner platforms
  get "/enterprises/:enterprise_id/actions/hosted-runners/platforms", operation_id: "actions/get-hosted-runners-platforms-for-enterprise" do
    enterprise = find_enterprise!
    confirm_api_enabled!(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_larger_runners_and_launch_ready!(entity: enterprise, actor: current_user)

    platforms = Actions::Image.curated_images_for(enterprise)
      .chain(Actions::Image.marketplace_images_for(enterprise))
      .map { |p| p.platform }
      .uniq
      .sort

    deliver :larger_runner_platforms_hash, { platforms: platforms }
  end

  # Get Enterprise hosted runner
  get "/enterprises/:enterprise_id/actions/hosted-runners/:hosted_runner_id", operation_id: "actions/get-hosted-runner-for-enterprise" do
    ent = find_enterprise!
    confirm_api_enabled!(ent)

    control_access :read_enterprise_self_hosted_runners,
      resource: ent,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_larger_runners_and_launch_ready!(entity: ent, actor: current_user)

    resp = handle_twirp_errors do
      Launch::Twirp::larger_runners_client.get_pool(
        ent,
        pool_id: int_id_param!(key: :hosted_runner_id, halt: true)
      )
    end

    deliver_error! 404 unless resp&.pool.present?

    pool = resp.pool
    image_details = get_image_details(image: pool.image, entity: ent)
    machine_spec_details = get_machine_spec_details(machine_spec_id: pool.machine_spec_id, entity: ent)

    deliver  :larger_runner_hash, {
      pool: pool,
      image: image_details,
      size: machine_spec_details,
      custom_image_generation_feature_enabled: is_custom_image_generation_enabled?(entity: ent)
      }, status: 200
  end

  # Create Enterprise hosted runner
  post "/enterprises/:enterprise_id/actions/hosted-runners", operation_id: "actions/create-hosted-runner-for-enterprise" do
    enterprise = find_enterprise!
    confirm_api_enabled!(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_larger_runners_and_launch_ready!(entity: enterprise, actor: current_user)

    data = receive_with_openapi
    name = data["name"]
    image = data["image"]
    runner_group_id = data["runner_group_id"]
    maximum_runners = data["maximum_runners"] || 50 # default amount we have on UI
    size = data["size"]
    enable_static_ip = data["enable_static_ip"] || false
    image_gen = data["image_gen"] && is_custom_image_generation_enabled?(entity: enterprise) || false

    if is_custom_images_policy_feature_enabled?(entity: enterprise)
      if image_gen && !::HostedRunnersHelper::is_custom_images_permitted?(enterprise)
        deliver_error! 422, message: "Custom image generation is disabled by your enterprise administrator."
      end
    end

    if is_public_ip_creation_forbidden?(entity: enterprise, is_public_ip_enabled: enable_static_ip)
      deliver_error! 422, message: "Unable to create public IP enabled GitHub-hosted runner, as you've reached your usage limit. Please disable public IPs for another runner or contact support at https://support.github.com/contact for additional information or help."
    end

    if is_runner_group_id_missing?(entity: enterprise, runner_group_id: runner_group_id)
      deliver_error! 422, message: "Invalid value for runner group ID"
    end

    maximum_runners_valid = maximum_runners >= ::Actions::LargerRunner::MAX_RUNNERS_LOWER_LIMIT && maximum_runners <= ::Actions::LargerRunner::MAX_RUNNERS_UPPER_LIMIT
    if !maximum_runners_valid
      deliver_error! 422, message: "Invalid value for maximum runners, must be between #{::Actions::LargerRunner::MAX_RUNNERS_LOWER_LIMIT} and #{::Actions::LargerRunner::MAX_RUNNERS_UPPER_LIMIT}."
    end

    image_version = image["version"] || "latest"
    image_details = get_image_details_from_request(id: image["id"], source: image["source"], entity: enterprise)
    if !image_details
      deliver_error! 422, message: "Invalid value for image ID or image source"
    end

    if image_version != "latest" && image_details.source != :Custom
      deliver_error! 422, message: "Invalid value for image.version, the only allowed value is 'latest'"
    end

    machine_spec_details = get_machine_spec_details(machine_spec_id: size, entity: enterprise)
    if !machine_spec_details
      deliver_error! 422, message: "Invalid value for machine size"
    end

    runner = Actions::LargerRunner.new(
      name: name,
      platform: image_details.platform,
      image: Actions::LargerRunner::ImageKey.new(source: image_details.source, id: image_details.id.to_s, version: image_version),
      runner_group_id: runner_group_id.to_i,
      labels: [],
      maximum_runners: maximum_runners.to_i,
      machine_spec_id: size,
      is_public_ip_enabled: enable_static_ip,
      image_sas_uri: "",
      persistent_os_disk: image_gen
    )

    resp = handle_twirp_errors do
      create_larger_runners_for(enterprise, larger_runner: runner, actor: current_actor)
    end

    pool = resp&.pool

    deliver :larger_runner_hash, {
      pool: pool,
      image: image_details,
      size: machine_spec_details,
      custom_image_generation_feature_enabled: is_custom_image_generation_enabled?(entity: enterprise)
    }, status: 201
  end

  # Update Enterprise hosted runner
  patch "/enterprises/:enterprise_id/actions/hosted-runners/:hosted_runner_id", operation_id: "actions/update-hosted-runner-for-enterprise" do
    enterprise = find_enterprise!
    confirm_api_enabled!(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_larger_runners_and_launch_ready!(entity: enterprise, actor: current_user)

    pool_id = int_id_param!(key: :hosted_runner_id, halt: true)

    data = receive_with_openapi
    name = data["name"]
    runner_group_id = data["runner_group_id"]
    maximum_runners = data["maximum_runners"]
    enable_static_ip = data["enable_static_ip"]
    image_version = data["image_version"]

    if is_public_ip_change_forbidden?(entity: enterprise, enable_public_ip: enable_static_ip, runner_id: pool_id)
      deliver_error! 422, message: "Unable to update GitHub-hosted runner, as you've reached public IP usage limit. Please disable public IPs for another runner or contact support at #{GitHub.contact_support_url} for additional information or help."
    end

    if runner_group_id && is_runner_group_id_missing?(entity: enterprise, runner_group_id: runner_group_id)
      deliver_error! 422, message: "Invalid value for runner group ID"
    end

    if maximum_runners
      maximum_runners_valid = maximum_runners >= ::Actions::LargerRunner::MAX_RUNNERS_LOWER_LIMIT && maximum_runners <= ::Actions::LargerRunner::MAX_RUNNERS_UPPER_LIMIT

      if !maximum_runners_valid
        deliver_error! 422, message: "Invalid value for maximum runners, must be between #{::Actions::LargerRunner::MAX_RUNNERS_LOWER_LIMIT} and #{::Actions::LargerRunner::MAX_RUNNERS_UPPER_LIMIT}."
      end
    end

    runner = Actions::LargerRunner.get_larger_runner(enterprise, pool_id: pool_id)
    deliver_error! 404 unless runner.present?

    image_details = get_image_details(image: runner.image, entity: enterprise)
    machine_spec_details = get_machine_spec_details(machine_spec_id: runner.machine_spec_id, entity: enterprise)

    all_labels = runner.labels.filter_map { |label| label.name unless label.type == "system" }

    runner_image = T.must(runner.image)
    if image_version && image_version != "latest" && runner_image.source != :Custom
      deliver_error! 422, message: "Invalid value for image_version, the only allowed value is 'latest'"
    end

    image = Actions::LargerRunner::ImageKey.new(source: runner_image.source, id: runner_image.id, version: image_version || runner_image.version)

    runner = Actions::LargerRunner.new(
      id: pool_id,
      runner_group_id: runner_group_id ? runner_group_id.to_i : runner.runner_group_id,
      name: name || runner.name,
      labels: all_labels,
      maximum_runners: maximum_runners || runner.maximum_runners,
      machine_spec_id: runner.machine_spec_id,
      is_public_ip_enabled: enable_static_ip.nil? ? runner.is_public_ip_enabled : enable_static_ip,
      image: image,
    )
    resp = handle_twirp_errors do
      update_larger_runners_for(enterprise, larger_runner: runner, actor: current_actor)
    end

    pool = resp&.pool

    deliver  :larger_runner_hash, {
      pool: pool,
      image: image_details,
      size: machine_spec_details,
      custom_image_generation_feature_enabled: is_custom_image_generation_enabled?(entity: enterprise) }, status: 200
  end

  # delete Enterprise hosted runner
  delete "/enterprises/:enterprise_id/actions/hosted-runners/:hosted_runner_id", operation_id: "actions/delete-hosted-runner-for-enterprise" do
    enterprise = find_enterprise!
    confirm_api_enabled!(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_larger_runners_and_launch_ready!(entity: enterprise, actor: current_user)

    pool_id = int_id_param!(key: :hosted_runner_id, halt: true)

    runner = Actions::LargerRunner.get_larger_runner(enterprise, pool_id: pool_id)
    deliver_error! 404 unless runner.present?

    image_details = get_image_details(image: runner.image, entity: enterprise)
    machine_spec_details = get_machine_spec_details(machine_spec_id: runner.machine_spec_id, entity: enterprise)

    resp = handle_twirp_errors do
      delete_larger_runners_for(enterprise, id: pool_id, actor: current_actor)
    end

    pool = resp&.pool

    deliver  :larger_runner_hash, {
      pool: pool,
      image: image_details,
      size: machine_spec_details,
      custom_image_generation_feature_enabled: is_custom_image_generation_enabled?(entity: enterprise) }, status: 202
  end
end
