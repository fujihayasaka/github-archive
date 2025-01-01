# typed: true
# frozen_string_literal: true
require "github-launch"

class Actions::ImageVersion

  attr_reader :version, :state, :failure_reason, :size, :created_on, :last_used_on
  def initialize(version:, state:, failure_reason: nil, size: nil, created_on: nil, last_used_on: nil)
    @version = version
    @state = state
    @failure_reason = failure_reason
    @size = size
    @created_on = created_on
    @last_used_on = last_used_on
  end

  def self.custom_image_versions_for_image(owner, image_id:)
    resp = Launch::Twirp::larger_runners_client.list_image_versions(owner, image_definition_id: image_id)

    from_rpc_collection(resp.value&.image_versions || [])
  end

  def self.custom_image_versions_for_image_including_latest(owner, image_id:)
    image_versions = custom_image_versions_for_image(owner, image_id: image_id)
    return image_versions if image_versions.empty?

    image_versions.unshift(new(version: "latest", state: :Ready, failure_reason: :None))
  end

  def self.from_rpc_collection(entities)
    entities.map { |entity| from_rpc_object(entity) }
  end

  def self.from_rpc_object(entity)
    return nil if entity.nil?

    new(
      version: entity.version,
      state: entity.state,
      failure_reason: entity.failure_reason,
      size: entity.size&.value,
      created_on: entity.created_on&.to_time,
      last_used_on: entity.last_used_on&.value
    )
  end
end
