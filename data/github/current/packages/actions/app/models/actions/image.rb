# typed: true
# frozen_string_literal: true

require "github-launch"

class Actions::Image

  attr_reader :id, :display_name, :latest_version_size_gb, :source, :versions_count, :total_versions_size, :latest_version, :state, :os_type, :architecture, :enabled

  def initialize(id:, display_name:, os_type:, architecture:, latest_version_size_gb: 0, source:, versions_count: 0, total_versions_size: 0, latest_version: nil, state: nil, enabled: false)
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
  end

  sig { returns(String) }
  def platform
    os_type = @os_type == "Windows" ? "win" : @os_type.downcase
    architecture = @architecture.downcase
    "#{os_type}-#{architecture}"
  end

  sig { params(owner: T.any(Organization, Business)).returns(T::Array[Actions::Image]) }
  def self.curated_images_for(owner)
    if GitHub.flipper[:larger_runners_use_curated_images_from_ims].enabled?(owner)
      resp = ims_curated_images_client.list_curated_image_definitions(owner: owner, include_disabled: false)
      from_ims_rpc_collection(resp.value&.image_definitions || [], :Curated)
    else
      resp = Launch::Twirp::larger_runners_client.list_curated_images(owner)
      from_rpc_collection(resp.value&.images || [], :Curated)
    end
  end

  sig { params(owner: T.any(Organization, Business)).returns(T::Array[Actions::Image]) }
  def self.marketplace_images_for(owner)
    resp = Launch::Twirp::larger_runners_client.list_marketplace_images(owner)

    from_rpc_collection(resp.value&.images || [], :Marketplace)
  end

  sig { params(owner: T.any(Organization, Business)).returns(T::Array[Actions::Image]) }
  def self.custom_images_for(owner)
    if GitHub.flipper[:larger_runners_use_custom_images_from_ims].enabled?(owner)
      resp = ims_customer_images_client.list_customer_image_definitions(owner: owner)

      from_ims_rpc_collection(resp.value&.image_definitions || [], :Custom)
    else
      resp = Launch::Twirp::larger_runners_client.list_image_definitions(owner)

      from_rpc_custom_image_definition_collection(resp.value&.image_definitions || [], :Custom)
    end
  end

  sig { params(owner: T.any(Organization, Business), image_id: Integer).returns(T.nilable(Actions::Image)) }
  def self.custom_image_for(owner, image_id:)
    if GitHub.flipper[:larger_runners_use_custom_images_from_ims].enabled?(owner)
      resp = ims_customer_images_client.get_customer_image_definition(owner: owner, image_definition_id: image_id)

      from_ims_rpc_image_definition_object(resp.value&.image_definition || nil, :Custom)
    else
      resp = Launch::Twirp::larger_runners_client.get_image_definition(owner, image_definition_id: image_id)

      from_rpc_custom_image_definition_object(resp.value&.image_definition || nil, :Custom)
    end
  end

  sig { params(entities: T.untyped, source: Symbol).returns(T::Array[Actions::Image]) }
  def self.from_ims_rpc_collection(entities, source)
    Array.wrap(entities.filter_map { |entity| from_ims_rpc_image_definition_object(entity, source) })
  end

  sig { params(entities: T.untyped, source: Symbol).returns(T::Array[Actions::Image]) }
  def self.from_rpc_collection(entities, source)
    # Remove nil entries, ensure single objects are returned as an array
    Array.wrap(entities.filter_map { |entity| from_rpc_object(entity, source) })
  end

  sig { params(entities: T.untyped, source: Symbol).returns(T::Array[Actions::Image]) }
  def self.from_rpc_custom_image_definition_collection(entities, source)
    # Remove nil entries, ensure single objects are returned as an array
    Array.wrap(entities.filter_map { |entity| from_rpc_custom_image_definition_object(entity, source) })
  end

  sig { params(entity: T.untyped, source: Symbol).returns(T.nilable(Actions::Image)) }
  def self.from_rpc_object(entity, source)
    return nil if entity.nil? || entity.id.empty?

    new(
      id: entity.id,
      display_name: entity.display_name,
      latest_version_size_gb: entity.size_gb,
      source: source,
      os_type: platform_to_ostype(entity.platform),
      architecture: platform_to_architecture(entity.platform),
    )
  end

  sig { params(entity: T.untyped, source: Symbol).returns(T.nilable(Actions::Image)) }
  def self.from_ims_rpc_image_definition_object(entity, source)
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
      state: "Ready",
    )
  end

  sig { params(entity: T.untyped, source: Symbol).returns(T.nilable(Actions::Image)) }
  def self.from_rpc_custom_image_definition_object(entity, source)
    return nil if entity.nil? || entity.id.nil?

    new(
      id: entity.id,
      display_name: entity.name,
      os_type: platform_to_ostype(entity.platform),
      architecture: platform_to_architecture(entity.platform),
      latest_version_size_gb: nil,
      source: source,
      versions_count: entity.versionCount,
      total_versions_size: entity.totalVersionsSize,
      latest_version: entity.latestVersion.nil? ? nil : entity.latestVersion.value,
      state: entity.state
    )
  end

  def self.platform_to_ostype(platform)
    return "Windows" if platform.present? && platform.start_with?("win-")
    "Linux"
  end

  def self.platform_to_architecture(platform)
    return "Arm64" if platform.present? && platform.end_with?("-arm64")
    "X64"
  end

  sig { returns(HostedComputeIms::Twirp::CuratedImagesClient) }
  def self.ims_curated_images_client
    ::HostedComputeIms::Twirp::CuratedImagesClient.new
  end

  sig { returns(HostedComputeIms::Twirp::CustomerImagesClient) }
  def self.ims_customer_images_client
    ::HostedComputeIms::Twirp::CustomerImagesClient.new
  end
end
