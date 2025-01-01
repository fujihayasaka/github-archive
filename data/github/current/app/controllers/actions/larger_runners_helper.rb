# typed: true
# frozen_string_literal: true

require "github-launch"
require "github/launch_client"
require "network_bundle/network_configuration_client"

# Helper methods useful in API and view controllers, as well as jobs.
module Actions::LargerRunnersHelper
  extend ActiveSupport::Concern
  include Kernel

  private

  sig { params(owner: T.any(Organization, Business), larger_runner: Actions::LargerRunner, actor: T.nilable(User)).returns(TwirpResponse) }
  def create_larger_runners_for(owner, larger_runner:, actor:)
    resp = Launch::Twirp::larger_runners_client.create_pool(
      owner,
      name: larger_runner.name,
      platform: larger_runner.platform,
      image: T.must(larger_runner.image),
      runner_group_id:  larger_runner.runner_group_id.to_i,
      labels: larger_runner.labels,
      maximum_runners:  larger_runner.maximum_runners.to_i,
      machine_spec_id:  larger_runner.machine_spec_id,
      is_public_ip_enabled:  larger_runner.is_public_ip_enabled,
      image_sas_uri: larger_runner.image_sas_uri,
      persistent_os_disk: larger_runner.persistent_os_disk,
    )

    if resp.call_succeeded?
      payload = convert_to_payload(larger_runner, pool_id: resp.value&.pool&.id)
      send_instrumentation_event(actor: actor, key: "create", owner: owner, payload: payload)
    end

    resp
  end

  sig { params(owner: T.any(Organization, Business), larger_runner: Actions::LargerRunner, actor: T.nilable(User)).returns(TwirpResponse) }
  def update_larger_runners_for(owner, larger_runner:, actor:)
    resp = Launch::Twirp::larger_runners_client.update_pool(
      owner,
      pool_id: larger_runner.id,
      name: larger_runner.name,
      labels: larger_runner.labels,
      runner_group_id: larger_runner.runner_group_id,
      maximum_runners:  larger_runner.maximum_runners.to_i,
      machine_spec_id: larger_runner.machine_spec_id,
      is_public_ip_enabled:  larger_runner.is_public_ip_enabled,
      image: T.must(larger_runner.image),
    )

    if resp.call_succeeded?
      payload = convert_to_payload(larger_runner)
      send_instrumentation_event(actor: actor, key: "update", owner: owner, payload: payload)
    end

    resp
  end

  sig { params(owner: T.any(Organization, Business), id: Integer, actor: T.nilable(User)).returns(TwirpResponse) }
  def delete_larger_runners_for(owner, id:, actor:)
    resp = Launch::Twirp::larger_runners_client.delete_pool(owner, pool_id: id)

    if resp.call_succeeded?
      send_instrumentation_event(actor: actor, key: "destroy", owner: owner, payload: {
        pool_id: id
      })
    end

    resp
  end

  sig { params(actor: T.nilable(User), key: String, payload: T::Hash[String, T.untyped], owner: T.any(Organization, Business)).void }
  def send_instrumentation_event(actor:, key:, payload:, owner:)
    payload.tap do |h|
      h[:actor] = actor
      h[:user] = actor if actor.is_a?(User)
      if owner.is_a?(Organization)
        h[:org] = owner
        h[:business] = owner.business if owner.business.present?
      elsif owner.is_a?(Business)
        h[:business] = owner
      end
    end

    GitHub.instrument("github_hosted_runner.#{key}", payload)
  end

  sig { params(larger_runner: Actions::LargerRunner, pool_id: T.nilable(Integer)).returns(Hash) }
  def convert_to_payload(larger_runner, pool_id: nil)
    payload = {
      pool_id: pool_id || larger_runner.id,
      name: larger_runner.name,
      runner_group_id: larger_runner.runner_group_id,
      labels: larger_runner.labels,
      platform: larger_runner.platform,
      runner_count: larger_runner.runner_count,
      image: convert_image_key(larger_runner.image),
      machine_spec_id: larger_runner.machine_spec_id,
      is_public_ip_enabled: larger_runner.is_public_ip_enabled,
      maximum_runners: larger_runner.maximum_runners
    }

    payload.tap do |h|
      h[:image_sas_uri] = larger_runner.image_sas_uri if larger_runner.try(:image_sas_uri)
    end
  end

  sig { params(image_key: T.nilable(Actions::LargerRunner::ImageKey)).returns(T.nilable(String)) }
  def convert_image_key(image_key)
    return nil unless image_key
    source = "Image source: #{image_key.source} " if image_key.source
    id = "Image id: #{image_key.id} " if image_key.id
    version = "version: #{image_key.version}" if image_key.version

    "#{source}#{id}#{version}"
  end

  def labels_for(owner, pool_id: nil)

    if owner.feature_enabled?(:actions_runners_use_runner_admin_service)
      runner_admin_client = GitHub.build_runner_admin_client(owner)
      resp = runner_admin_client.list_labels(owner: owner)
    else
      resp = Launch::Twirp.self_hosted_runners_client.list_labels(owner)
    end

    self_hosted_labels = resp.value&.labels&.map(&:name) || []

    # Labels are not objects in the larger runner service (they're just a bag of strings)
    resp = Launch::Twirp::larger_runners_client.list_labels(owner)
    custom_runner_labels = resp.value&.labels || []

    # Get the unique set of labels (case-insensitive), preferring the custom runner labels casing
    labels = (custom_runner_labels + self_hosted_labels).uniq(&:downcase)

    # Fake filtering out system variables. This would otherwise be:
    #   labels.select { |label| label.type != "system" }
    system_labels = %w[self-hosted macos windows linux x64 x32]

    unless pool_id.nil?
      larger_runner = Actions::LargerRunner.get_larger_runner(owner, pool_id: pool_id)
      if larger_runner.present?
        # Include the pool's name as a system label since it's enforced in the runner service
        system_labels.push(larger_runner.name)
      end
    end

    # Remove system labels and re-order since we merged two lists. We don't need to give the labels an ID
    # since they're not used in the UI or when persisted back to the runner service.
    labels.reject { |label| system_labels.any? { |sl| label.casecmp?(sl) } || label.start_with?("_runnersvcpool-") }
      .sort_by(&:downcase)
      .map { |label| GitHub::Launch::Services::Selfhostedrunners::Label.new(name: label, id: -1, type: :user) }
  end

  def is_custom_images_enabled?(entity:)
    # New system (generation via Actions workflows)
    is_custom_image_generation_enabled?(entity: entity) ||
    # Old system (uploading a custom image SAS URI)
    is_custom_image_uploading_enabled?(entity: entity)
  end

  def is_custom_images_api_enabled?(entity:)
    GitHub.flipper[:larger_runners_custom_images_api].enabled? ||
    entity.feature_enabled?(:larger_runners_custom_images_api)
  end

  def is_custom_image_generation_enabled?(entity:)
    GitHub.flipper[:larger_runners_custom_image_generation].enabled? ||
    entity.feature_enabled?(:larger_runners_custom_image_generation)
  end

  def is_custom_image_uploading_enabled?(entity:)
    GitHub.flipper[:actions_custom_image].enabled? ||
    entity.feature_enabled?(:actions_custom_image)
  end

  def is_custom_images_policy_feature_enabled?(entity:)
    GitHub.flipper[:actions_enforce_custom_image_policy].enabled? ||
    entity.feature_enabled?(:actions_enforce_custom_image_policy)
  end

  def is_bypass_gpu_maximum_runners_enabled?(entity:)
    GitHub.flipper[:larger_runners_bypass_gpu_maximum_runners].enabled? ||
    GitHub.flipper[:larger_runners_bypass_gpu_maximum_runners].enabled?(get_billing_owner_from_entity(entity))
  end

  def is_increase_gpu_maximum_runners_enabled?(entity:)
    GitHub.flipper[:larger_runners_increase_gpu_maximum_runners].enabled? ||
    GitHub.flipper[:larger_runners_increase_gpu_maximum_runners].enabled?(get_billing_owner_from_entity(entity))
  end

  def gpu_maximum_runners_for(entity:)
    return ::Actions::LargerRunner::MAX_RUNNERS_UPPER_LIMIT if is_bypass_gpu_maximum_runners_enabled?(entity: entity)

    # TODO: make it a default one after going to public beta and enabling FF for everyone
    return ::Actions::LargerRunner::MAX_GPU_RUNNERS_UPPER_INCREASED_LIMIT if is_increase_gpu_maximum_runners_enabled?(entity: entity)

    ::Actions::LargerRunner::MAX_GPU_RUNNERS_UPPER_LIMIT
  end

  def is_runner_group_id_missing?(entity:, runner_group_id:)
    Actions::RunnerGroup.for_entity(entity, include_runners: true).detect { |r| r.id == runner_group_id }.nil?
  end

  def is_public_ip_limit_reached?(current_ip_usage:, usage_limit:)
    current_ip_usage >= usage_limit
  end

  def is_public_ip_change_forbidden?(entity:, enable_public_ip:, runner_id:)
    runners_with_public_ip = Actions::LargerRunner.larger_runners_for(entity: entity, is_public_ip_enabled: true)
    runner_under_update = runners_with_public_ip.find { |runner| runner.id == runner_id }

    return false if !runner_under_update && !enable_public_ip

    # The goal of this method is to determine if a new public IP is being enabled and is at risk of exceeding the limit.
    public_ip_is_changed = runner_under_update&.is_public_ip_enabled != enable_public_ip
    turning_off_public_ip = runner_under_update&.is_public_ip_enabled && !enable_public_ip

    is_public_ip_limit_reached?(current_ip_usage: runners_with_public_ip.count, usage_limit:  public_ip_usage_limit_for(entity)) && public_ip_is_changed && !turning_off_public_ip
  end

  def is_public_ip_creation_forbidden?(entity:, is_public_ip_enabled:)
    runners_with_public_ip = Actions::LargerRunner.larger_runners_for(entity: entity, is_public_ip_enabled: true)
    is_public_ip_limit_reached = is_public_ip_limit_reached?(current_ip_usage: runners_with_public_ip.count, usage_limit: public_ip_usage_limit_for(entity))

    is_public_ip_enabled && (is_public_ip_limit_reached || !is_public_ip_allowed_for_entity?(entity))
  end

  def public_ip_usage_limit_for(entity)
    billing_entity = get_billing_owner_from_entity(entity)

    feature_flag_200 = GitHub.flipper[:custom_hosted_runner_raise_public_ip_limit_200]
    return ::Actions::LargerRunner::PublicIPSettings::INCREASED_UPPER_PUBLIC_IP_LIMIT_200 if feature_flag_200.enabled?(entity) || feature_flag_200.enabled?(billing_entity)

    feature_flag_50 = GitHub.flipper[:custom_hosted_runner_raise_public_ip_limit]
    return ::Actions::LargerRunner::PublicIPSettings::INCREASED_UPPER_PUBLIC_IP_LIMIT_50 if feature_flag_50.enabled?(entity) || feature_flag_50.enabled?(billing_entity)

    ::Actions::LargerRunner::PublicIPSettings::STANDARD_UPPER_PUBLIC_IP_LIMIT
  end

  def is_public_ip_allowed_for_entity?(entity)
    return true unless GitHub.flipper[:custom_hosted_runners_limit_public_ip_enterprise_only].enabled?(entity)
    entity.plan.business_plus?
  end

  def get_billing_owner_from_entity(entity)
    if entity.is_a?(Organization)
      entity.business.present? ? entity.business : entity
    else
      entity.is_a?(Business) ? entity : nil
    end
  end

  def larger_runners_machine_specs(owner, actor: nil)
    Actions::MachineSpec.machine_specs_for(owner)
  end

  def larger_runners_curated_images(owner)
    Actions::Image.curated_images_for(owner)
  end

  def larger_runners_marketplace_images(owner)
    Actions::Image.marketplace_images_for(owner)
  end

  def larger_runners_custom_images(owner)
    Actions::Image.custom_images_for(owner)
  end

  def larger_runner_all_images(owner)
    @_larger_runner_all_images_by_owner ||= {}
    @_larger_runner_all_images_by_owner[owner.id] ||= larger_runners_curated_images(owner) + larger_runners_marketplace_images(owner)
  end

  def image_name_for(runner, owner)
    if runner.image&.source == :Custom
      image_name = larger_runners_custom_images(owner).find { |image| image.id.to_i == runner.image&.id.to_i }&.display_name
      if image_name.blank?
        return "#{runner.image&.id} (#{runner.image&.version})"
      else
        return "#{image_name} (#{runner.image&.version})"
      end
    end

    image_details = larger_runner_all_images(owner).find { |image| image.id == runner.image&.id }
    return runner.image&.id if image_details.nil?

    os_label = runner.platform == "linux-x64" || runner.platform == "linux-arm64" ? "Ubuntu" : "Windows"
    if image_details.display_name.include?(os_label)
      image_details.display_name
    else
      "#{os_label} #{image_details.display_name}"
    end
  end

  def image_source_for(runner)
    case runner.image&.source
    when :Curated
      "GitHub-owned"
    when :Marketplace
      "Partner"
    when :Custom
      "Custom"
    else
      nil
    end
  end

  def image_source_is_alpha_for(runner)
    runner.image&.source == :Custom
  end

  def image_source_is_custom_for(runner)
    runner.image&.source == :Custom
  end

  def platform_name_for(runner)
    case runner.platform
    when "linux-x64"
      "Linux x64"
    when "win-x64"
      "Windows x64"
    when "linux-arm64"
      "Linux ARM64"
    when "win-arm64"
      "Windows ARM64"
    else
      nil
    end
  end

  def custom_image_versions_for_runner(owner, larger_runner:)
    if larger_runner.image&.source == :Custom
      custom_image_versions_for_image(owner, image_id: larger_runner.image.id.to_i)
    else
      nil
    end
  end

  def custom_image_versions_for_image(owner, image_id:)
    Actions::ImageVersion.custom_image_versions_for_image(owner, image_id: image_id)
  end

  def is_vnet_injection_enabled?(actor, runner_group_id)
    begin
      resources = network_configuration_client.get_compute_resources(actor, "actions", runner_group_id)

      return false if resources.nil?
      return false if !resources.service.casecmp?("actions")

      network_configuration = resources.network_configuration
      return false if network_configuration.nil?
      return false if !network_configuration.enabled

      network_resource = network_configuration.network_resources.find { |nr| nr.state.casecmp?("Registered") }
      return false if network_resource.nil?

      !network_resource.subnet_id.blank?
    rescue ::NetworkBundle::NetworkConfigurationsException
      # ignore
      false
    end
  end

  def ensure_tenant_exists(entity:)
    if entity.respond_to?(:business) && entity.business.present?
      result = Launch::Twirp.deployer_client.setup_tenant(entity.business)
      raise Timeout::Error, "Timeout fetching tenant" unless result.call_succeeded?
    end

    result = Launch::Twirp.deployer_client.setup_tenant(entity)
    raise Timeout::Error, "Timeout fetching tenant" unless result.call_succeeded?
  end

  def network_configuration_client
    NetworkBundle::NetworkConfigurationClient.create
  end

  def should_disable_gpu_runners_for_untrusted?(owner)
    return false unless GitHub.flipper[:larger_runners_hide_gpu_runners_for_untrusted_tier].enabled?(owner)

    tier_result = TrustTiers::Tier.for_billable_owner(owner)
    if tier_result&.tier == TrustTiers::Tier::TRUSTED || tier_result&.tier == TrustTiers::Tier::NEUTRAL
      false
    else
      true
    end
  end

  def ims_customer_images_client
    ::HostedComputeIms::Twirp::CustomerImagesClient.new
  end

  def check_image_version_pattern(version, pattern)
    escaped = Regexp.escape(pattern).gsub("\\*", ".*?")
    pattern_regex = Regexp.new "^#{escaped}$", Regexp::IGNORECASE
    !!(version =~ pattern_regex)
  end
end
