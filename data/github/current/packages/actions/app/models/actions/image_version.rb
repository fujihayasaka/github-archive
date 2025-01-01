# typed: true
# frozen_string_literal: true

require "github-launch"

class Actions::ImageVersion

  STATE_TRANSLATION = {
    ImportingBlob: :Provisioning,
    ImportFailed: :ProvisionFailed,
    ProvisioningImageVersion: :Provisioning,
  }.freeze

  attr_reader :version, :state, :state_details, :size, :created_on, :last_used_on
  def initialize(version:, state:, state_details: nil, size: nil, created_on: nil, last_used_on: nil)
    @version = version
    @state = state
    @state_details = state_details
    @size = size
    @created_on = created_on
    @last_used_on = last_used_on
  end

  def self.custom_image_versions_for_image(owner, image_id:)
    if FeatureFlag.vexi.enabled?(:larger_runners_use_custom_images_from_ims, owner, default: false)
      resp = HostedComputeIms::Twirp.customer_images_client.list_customer_image_versions(owner: owner, image_definition_id: image_id)
      from_rpc_ims_collection(resp.value&.image_versions || [])
    else
      resp = Launch::Twirp::larger_runners_client.list_image_versions(owner, image_definition_id: image_id)

      from_rpc_collection(resp.value&.image_versions || [])
    end
  end

  def self.custom_image_versions_for_image_including_latest(owner, image_id:)
    image_versions = custom_image_versions_for_image(owner, image_id: image_id)
    return image_versions if image_versions.empty?

    image_versions.unshift(new(version: "latest", state: :Ready, state_details: :None))
  end

  def self.from_rpc_collection(entities)
    entities.map { |entity| from_rpc_object(entity) }
  end

  def self.from_rpc_ims_collection(entities)
    entities.map { |entity| from_rpc_ims_object(entity) }
  end

  def self.from_rpc_object(entity)
    return nil if entity.nil?

    new(
      version: entity.version,
      state: STATE_TRANSLATION[entity.state] || entity.state,
      state_details: entity.failure_reason,
      size: entity.size&.value,
      created_on: entity.created_on&.to_time,
      last_used_on: entity.last_used_on&.value
    )
  end

  def self.from_rpc_ims_object(entity)
    return nil if entity.nil?

    new(
      version: entity.version,
      state: entity.state,
      state_details: entity.state_details,
      size: entity.size_gb,
      created_on: entity.created_at&.to_time,
      last_used_on: nil,
    )
  end
end
