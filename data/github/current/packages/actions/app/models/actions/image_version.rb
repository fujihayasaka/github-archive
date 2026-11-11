# typed: true
# frozen_string_literal: true

require "github-launch"

class Actions::ImageVersion

  STATE_TRANSLATION = {
    ImportingBlob: :Provisioning,
    ImportFailed: :ProvisionFailed,
    ProvisioningImageVersion: :Provisioning,
  }.freeze

  attr_reader :version, :state, :state_details, :enabled, :size, :created_at, :last_used_at, :check_run_url, :source_image_type, :source_image_name, :source_image_version
  def initialize(version:, state:, enabled: true, state_details: nil, size: nil, created_at: nil, last_used_at: nil, check_run_url: nil, source_image_type: nil, source_image_name: nil, source_image_version: nil)
    @version = version
    @state = state
    @state_details = state_details
    @enabled = enabled
    @size = size
    @created_at = created_at
    @last_used_at = last_used_at
    @check_run_url = check_run_url
    @source_image_type = source_image_type
    @source_image_name = source_image_name
    @source_image_version = source_image_version
  end

  def self.custom_image_versions_for_image(owner, image_id:)
    resp = HostedComputeIms::Twirp.customer_images_client.list_customer_image_versions(owner: owner, image_definition_id: image_id)
    from_rpc_ims_collection(resp.value&.image_versions || [])
  end

  def self.custom_image_versions_for_image_including_latest(owner, image_id:)
    image_versions = custom_image_versions_for_image(owner, image_id: image_id)
    return image_versions if image_versions.empty?

    image_versions.unshift(new(version: "latest", state: :Ready, state_details: :None))
  end

  def self.from_rpc_ims_collection(entities)
    entities.map { |entity| from_rpc_ims_object(entity) }
  end

  def self.from_rpc_ims_object(entity)
    return nil if entity.nil?

    new(
      version: entity.version,
      state: entity.state,
      state_details: entity.state_details,
      enabled: entity.enabled,
      size: entity.size_gb,
      created_at: entity.created_at&.to_time,
      last_used_at: entity.last_used_at&.to_time,
      check_run_url: get_check_run_url(entity.check_run_id),
      source_image_type: get_source_image_type(entity.image_generation_source&.image_type),
      source_image_name: entity.image_generation_source&.image_name,
      source_image_version: entity.image_generation_source&.version
    )
  end

  def self.get_check_run_url(check_run_id)
    return nil if check_run_id.blank?

    begin
      _type, id = Platform::Helpers::NodeIdentification.from_global_id(check_run_id)
      return nil if id.nil? || id.to_i <= 0

      check_run = Checks.domain.check_runs.unsafe_for_id(id.to_i)
      return nil unless check_run&.respond_to?(:permalink)

      check_run.permalink
    rescue StandardError => e
      GitHub.logger.warn("Failed to retrieve check run URL", exception: e, check_run_id: check_run_id)
      nil
    end
  end

  def self.get_source_image_type(image_type)
    image_type == "Customer" ? "Custom" : image_type
  end

  private_class_method :get_check_run_url, :get_source_image_type
end
