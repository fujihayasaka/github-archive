# typed: true
# frozen_string_literal: true
require "github-launch"

class Actions::Image
  extend T::Sig

  attr_reader :id, :display_name, :size_gb, :platform, :source, :version_count, :total_versions_size, :latest_version, :state

  def initialize(id:, display_name:, size_gb: 0, platform:, source:, version_count: 0, total_versions_size: 0, latest_version: nil, state: nil)
    @id = id
    @display_name = display_name
    @size_gb = size_gb
    @platform = platform
    @source = source
    @version_count = version_count
    @total_versions_size = total_versions_size
    @latest_version = latest_version
    @state = state
  end

  sig { params(owner: T.any(Organization, Business)).returns(T::Array[Actions::Image]) }
  def self.curated_images_for(owner)
    resp = Launch::Twirp::larger_runners_client.list_curated_images(owner)

    from_rpc_collection(resp.value&.images || [], :Curated)
  end

  sig { params(owner: T.any(Organization, Business)).returns(T::Array[Actions::Image]) }
  def self.marketplace_images_for(owner)
    resp = Launch::Twirp::larger_runners_client.list_marketplace_images(owner)

    from_rpc_collection(resp.value&.images || [], :Marketplace)
  end

  sig { params(owner: T.any(Organization, Business)).returns(T::Array[Actions::Image]) }
  def self.custom_images_for(owner)
    resp = Launch::Twirp::larger_runners_client.list_image_definitions(owner)

    from_rpc_custom_image_definition_collection(resp.value&.image_definitions || [], :Custom)
  end

  sig { params(owner: T.any(Organization, Business), image_id: Integer).returns(T.nilable(Actions::Image)) }
  def self.custom_image_for(owner, image_id:)
    resp = Launch::Twirp::larger_runners_client.get_image_definition(owner, image_definition_id: image_id)

    from_rpc_custom_image_definition_object(resp.value&.image_definition || nil, :Custom)
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
      size_gb: entity.size_gb,
      platform: entity.platform,
      source: source
    )
  end

  sig { params(entity: T.untyped, source: Symbol).returns(T.nilable(Actions::Image)) }
  def self.from_rpc_custom_image_definition_object(entity, source)
    return nil if entity.nil? || entity.id.nil?

    new(
      id: entity.id,
      display_name: entity.name,
      size_gb: nil,
      platform: entity.platform,
      source: source,
      version_count: entity.versionCount,
      total_versions_size: entity.totalVersionsSize,
      latest_version: entity.latestVersion.nil? ? nil : entity.latestVersion.value,
      state: entity.state
    )
  end
end
