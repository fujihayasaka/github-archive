# typed: true
# frozen_string_literal: true

require "github-launch"

class Actions::Image
  STATE_TRANSLATION = {
    Provisioning: :ImageDefinitionReady,
    Ready: :ImageDefinitionReady,
    Deleting: :ImageDefinitionDeleting
  }.freeze

  attr_reader :id, :display_name, :latest_version_size_gb, :source, :versions_count, :total_versions_size, :latest_version, :state, :os_type, :architecture, :enabled, :owner_id, :runner_group_id, :is_image_generation_supported

  def initialize(id:, display_name:, os_type:, architecture:, latest_version_size_gb: 0, source:, versions_count: 0, total_versions_size: 0, latest_version: nil, state: nil, enabled: false, owner_id: nil, runner_group_id: 0, is_image_generation_supported: false)
    @id = id
    @display_name = display_name
    @os_type = os_type.to_s
    @architecture = architecture
    @latest_version_size_gb = latest_version_size_gb
    @source = source
    @versions_count = versions_count
    @total_versions_size = total_versions_size
    @latest_version = latest_version
    @state = state
    @enabled = enabled
    @owner_id = owner_id
    @runner_group_id = runner_group_id
    @is_image_generation_supported = is_image_generation_supported
  end

  sig { returns(String) }
  def platform
    os_type = @os_type == "Windows" ? "win" : @os_type.downcase
    architecture = @architecture.downcase
    "#{os_type}-#{architecture}"
  end

  sig { params(owner: T.any(Organization, Business)).returns(T::Array[Actions::Image]) }
  def self.curated_images_for(owner)
    resp = HostedComputeIms::Twirp.curated_images_client.list_curated_image_definitions(owner: owner, include_disabled: false)
    from_ims_rpc_collection(resp.value&.image_definitions || [], :Curated).select { |v| v.owner_id == "github" }
  end

  sig { params(owner: T.any(Organization, Business)).returns(T::Array[Actions::Image]) }
  def self.marketplace_images_for(owner)
    resp = HostedComputeIms::Twirp.curated_images_client.list_curated_image_definitions(owner: owner, include_disabled: false)
    from_ims_rpc_collection(resp.value&.image_definitions || [], :Marketplace).select { |v| v.owner_id == "partner" }
  end

  sig { params(owner: T.any(Organization, Business), runner_group_id: T.nilable(Integer)).returns(T::Array[Actions::Image]) }
  def self.custom_images_for(owner, runner_group_id: nil)
    resp = HostedComputeIms::Twirp.customer_images_client.list_customer_image_definitions(owner: owner, runner_group_id: runner_group_id)
    from_ims_rpc_collection(resp.value&.image_definitions || [], :Custom, is_image_generation_supported_from_custom_images: is_image_generation_supported_from_custom_images?(owner))
  end

  sig { params(owner: T.any(Organization, Business), image_id: Integer).returns(T.nilable(Actions::Image)) }
  def self.custom_image_for(owner, image_id:)
    resp = HostedComputeIms::Twirp.customer_images_client.get_customer_image_definition(owner: owner, image_definition_id: image_id)
    from_ims_rpc_image_definition_object(resp.value&.image_definition || nil, :Custom, is_image_generation_supported_from_custom_images: is_image_generation_supported_from_custom_images?(owner))
  end

  sig { params(owner: T.any(Organization, Business)).returns(T::Boolean) }
  def self.is_image_generation_supported_from_custom_images?(owner)
    FeatureFlag.vexi.enabled?(:larger_runners_custom_image_generation_for_custom_images, default: false) ||
      owner.feature_flag_enabled?(:larger_runners_custom_image_generation_for_custom_images, default: false)
  end

  sig { params(entities: T.untyped, source: Symbol, is_image_generation_supported_from_custom_images: T::Boolean).returns(T::Array[Actions::Image]) }
  def self.from_ims_rpc_collection(entities, source, is_image_generation_supported_from_custom_images: false)
    Array.wrap(entities.filter_map { |entity| from_ims_rpc_image_definition_object(entity, source, is_image_generation_supported_from_custom_images: is_image_generation_supported_from_custom_images) })
  end

  sig { params(entity: T.untyped, source: Symbol, is_image_generation_supported_from_custom_images: T::Boolean).returns(T.nilable(Actions::Image)) }
  def self.from_ims_rpc_image_definition_object(entity, source, is_image_generation_supported_from_custom_images: false)
    return nil unless entity.present? && entity.id.present?

    new(
      id: entity.id.to_s, # convert Id to string to be consistent with "Pool.image.id"
      display_name: entity.name,
      source: source,
      latest_version_size_gb: entity.latest_version_size_gb,
      os_type: entity.os_type,
      architecture: entity.architecture,
      enabled: entity.enabled,
      versions_count: entity.image_versions_count,
      total_versions_size: entity.total_image_versions_size_gb,
      latest_version: entity.latest_version,
      state: entity.state.to_sym,
      owner_id: entity.owner_id,
      runner_group_id: entity.runner_group_id&.value,
      is_image_generation_supported: entity.is_image_generation_supported || (source == :Custom && is_image_generation_supported_from_custom_images)
    )
  end

  def self.platform_to_ostype(platform)
    return "Windows" if platform.present? && platform.start_with?("win-")
    return "MacOS" if platform.present? && platform.start_with?("macos-")
    "Linux"
  end

  def self.platform_to_architecture(platform)
    return "Arm64" if platform.present? && platform.end_with?("-arm64")
    "X64"
  end
end
