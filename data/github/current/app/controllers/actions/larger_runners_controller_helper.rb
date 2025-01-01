# typed: true
# frozen_string_literal: true

require "github-launch"
require "github/launch_client"

# Helper methods useful in view controllers.
module Actions::LargerRunnersControllerHelper
  extend T::Helpers
  extend ActiveSupport::Concern
  include ::Actions::LargerRunnersHelper
  include ::Actions::LargerRunners::CustomImagesHelper

  private

  sig do
    params(
      owner: T.any(Organization, Business),
      runner_list_path: String,
      is_public_ip_allowed: T::Boolean,
      total_ip_count: Integer,
      used_ip_count: Integer,
    ).returns(T::Hash[String, T.untyped])
  end
  def build_new_runner_react_payload(owner:, runner_list_path:, is_public_ip_allowed:, total_ip_count:, used_ip_count:)
    disable_gpu_runners = should_disable_gpu_runners_for_untrusted?(owner)

    {
      isEnterprise: owner.is_a?(Business),
      runnerListPath: runner_list_path,
      entityLogin: owner.display_login,
      docsUrlBase: GitHub.help_url,
      isPublicIpAllowed: is_public_ip_allowed,
      totalIpCount: total_ip_count,
      usedIpCount: used_ip_count,
      maxConcurrentJobsDefault: ::Actions::LargerRunner::MAX_RUNNERS_DEFAULT,
      maxConcurrentJobsMin: ::Actions::LargerRunner::MAX_RUNNERS_LOWER_LIMIT,
      maxConcurrentJobsDefaultMax: ::Actions::LargerRunner::MAX_RUNNERS_UPPER_LIMIT,
      maxConcurrentJobsGpuMax: gpu_maximum_runners_for(entity: owner),
      isCustomImageUploadingEnabled: is_custom_image_uploading_enabled?(entity: owner),
      machineSpecs: get_transformed_machine_spec_models(entity: owner, disable_gpu_runners: disable_gpu_runners),
      runnerGroups: get_transformed_runner_groups_models(entity: owner),
      images: get_transformed_images_models(entity: owner),
      isCustomImagesFeatureEnabled: is_custom_images_enabled?(entity: owner),
    }
  end

  sig do
    params(
      owner: T.any(Organization, Business),
      larger_runner: Actions::LargerRunner,
      runner_list_path: String,
      is_public_ip_allowed: T::Boolean,
      total_ip_count: Integer,
      used_ip_count: Integer,
    ).returns(T::Hash[String, T.untyped])
  end
  def build_edit_runner_react_payload(owner:, larger_runner:, runner_list_path:, is_public_ip_allowed:, total_ip_count:, used_ip_count:)
    {
        docsUrlBase: GitHub.help_url,
        entityLogin: owner.display_login,
        imageVersions: get_transformed_image_versions_models(entity: owner, image: larger_runner.image),
        isEnterprise: owner.is_a?(Business),
        isPublicIpAllowed: is_public_ip_allowed,
        maxConcurrentJobsMax: larger_runner.machine_spec&.is_gpu_spec? ? gpu_maximum_runners_for(entity: owner) : ::Actions::LargerRunner::MAX_RUNNERS_UPPER_LIMIT,
        maxConcurrentJobsMin: ::Actions::LargerRunner::MAX_RUNNERS_LOWER_LIMIT,
        runnerGroupId: larger_runner.runner_group_id,
        runnerGroups: get_transformed_runner_groups_models(entity: owner),
        runnerHasCustomImage: is_custom_images_enabled?(entity: owner) && larger_runner.image&.source == :Custom,
        runnerHasGpuSpec: larger_runner.machine_spec&.is_gpu_spec?,
        runnerHasPublicIp: larger_runner.is_public_ip_enabled,
        runnerId: larger_runner.id,
        runnerImageVersion: larger_runner.image&.version,
        runnerListPath: runner_list_path,
        runnerMaxConcurrentJobs: larger_runner.maximum_runners,
        runnerName: larger_runner.name,
        totalIpCount: total_ip_count,
        usedIpCount: used_ip_count,
    }
  end

  sig do
    params(
      request: ActionDispatch::Request
    ).returns(T::Array[String])
  end
  def build_custom_tags(request)
    custom_tags = []

    # add referrer_controller_action tag
    router_response = Rails.application.routes.recognize_path(request.path, method: :get)
    controller = GitHub::TaggingHelper.formatted_controller(router_response[:controller])
    custom_tags << "referrer_controller_action:#{controller}##{router_response[:action]}"

    custom_tags
  end

  def submitted_machine_spec(machine_spec_id, owner)
    machine_specs = Actions::MachineSpec.machine_specs_for(owner)
    machine_specs.find { |ms| ms.id == machine_spec_id }
  end

  def is_vnet_and_public_ip_enabled(entity:, is_public_ip_enabled:, runner_group_id:)
    is_public_ip_enabled && is_vnet_injection_enabled?(entity, runner_group_id)
  end

  def convert_to_image_key(source:, image_id: "", version: nil)
    version = "latest" if version.nil?
    Actions::LargerRunner::ImageKey.new(source: source.to_sym, id: image_id, version: version)
  end

  def get_transformed_runner_groups_models(entity:)
    runner_groups = Actions::RunnerGroup.for_entity(entity).reject(&:inherited?).sort
    runner_groups.map do |group|
      group.as_json(only: %w[id name visibility allow_public precreated selected_targets])
        .transform_keys { |key| key.to_s.camelize(:lower) }
    end
  end

  def get_transformed_machine_spec_models(entity:, disable_gpu_runners:)
    machine_specs = larger_runners_machine_specs(entity)

    if disable_gpu_runners
      machine_specs = machine_specs.reject { |ms| ms.is_gpu_spec?  }
    end

    machine_specs.map do |machine_spec|
      gpu_info = machine_spec.gpu.nil? ? nil : machine_spec.gpu.as_json(only: %w[name count memory_gb]).transform_keys { |key| key.to_s.camelize(:lower) }
      machine_spec.as_json(only: %w[id architecture type storage_gb memory_gb cpu_cores documentation_url]).merge(
          gpu: gpu_info
        )
        .transform_keys { |key| key.to_s.camelize(:lower) }
    end
  end

  def get_transformed_images_models(entity:)
    mapped_keys = %w[id display_name source os_type architecture size_gb image_versions]
    curated_images = larger_runners_curated_images(entity)
    marketplace_images = larger_runners_marketplace_images(entity)
    custom_images = []

    if is_custom_images_enabled?(entity: entity)
      # Custom images with status :Deleting are excluded from runner creation UI
      custom_images = get_transformed_custom_images_models(entity: entity, exclude_deleting: true)
    end

    curated_images = curated_images.map do |image|
      is_image_generation_supported = is_image_generation_supported?(entity: entity, image: image)
      image.as_json(only: mapped_keys)
      .merge(isImageGenerationSupported: is_image_generation_supported)
      .transform_keys { |key| key.to_s.camelize(:lower) }
    end

    marketplace_images = marketplace_images.map do |image|
      is_image_generation_supported = is_image_generation_supported?(entity: entity, image: image)
      image.as_json(only: mapped_keys)
      .merge(isImageGenerationSupported: is_image_generation_supported)
      .transform_keys { |key| key.to_s.camelize(:lower) }
    end
    {
      github: curated_images,
      partner: marketplace_images,
      custom: custom_images,
    }
  end

  def is_image_generation_supported?(entity:, image:)

    return false unless is_custom_images_enabled?(entity: entity)
    return true if GitHub.flipper[:larger_runners_use_curated_images_from_ims].enabled?(entity) && image.source == :Curated && image.display_name.start_with?("Ubuntu ")
    [
      "canonical:0001-com-ubuntu-server-jammy:22_04-lts-arm64",
      "canonical:0001-com-ubuntu-server-focal:20_04-lts-arm64",
      "canonical:0001-com-ubuntu-server-jammy:22_04-lts",
      "canonical:0001-com-ubuntu-server-focal:20_04-lts",
      "arm:github_arm_linux_runner_2404:github_arm_linux_runner_plan_2404",
      "arm:github_arm_linux_runner:github_arm_linux_runner_plan",
      # "MicrosoftWindowsDesktop:windows11preview-arm64:win11-23h2-ent",
      "microsoftwindowsserver:windowsserver:2022-datacenter",
      "microsoftwindowsserver:windowsserver:2019-datacenter",
      "ubuntu-24.04",
      "ubuntu-22.04",
      "ubuntu-20.04",
      "ubuntu-18.04",
      "ubuntu-latest"
    ].include?(image.id)
  end

  def ensure_larger_runners_enabled(entity:, actor:, this_entity:)
    return if entity.can_use_larger_runners?

    if entity.is_eligible_to_onboard_larger_runners?
      entity.onboard_larger_runners(actor: actor)
      this_entity.reload # "this_organization" or "this_business" is alternative of "current_organization" or "current_business" and can cache old value
    else
      T.unsafe(self).render_404
    end
  end

  def ensure_custom_images_enabled(entity:)
    T.unsafe(self).render_404 unless is_custom_images_enabled?(entity: entity)
  end

  def error_invalid_group(is_update: false)
    "Failed to #{is_update ? "update" : "create"} GitHub-hosted runner because selected runner group is missing or has been deleted."
  end

  def error_invalid_public_ip(is_update: false)
    "Unable to #{is_update ? "update" : "create public IP enabled"} GitHub-hosted runner, as you've reached #{is_update ? "public IP" : "your"} usage limit. Please disable public IPs for another runner or contact support at #{GitHub.contact_support_url} for additional information or help."
  end

  def error_larger_runner_is_missing
    "Failed to update GitHub-hosted runner because runner is missing or has been deleted."
  end

  def error_larger_runner_is_invalid(is_update: false)
    "GitHub-hosted runner is being #{is_update ? "updated" : "created"} with faulty inputs."
  end

  def error_maximum_runner_is_invalid
    "Maximum runners setting is invalid."
  end

  def error_public_ip_vnet_conflict
    "Public IP cannot be used when the GitHub-hosted runner is in the same runner group that is using a private network."
  end

  def unknown_failure_message(is_update: false)
    "Failed to #{is_update ? "update" : "create"} GitHub-hosted runner. Please try again. If the problem persists, we recommend you check https://www.githubstatus.com/ to see the service status of actions or contact support at #{GitHub.contact_support_url} for additional information or help."
  end
end
