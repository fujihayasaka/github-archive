# typed: true
# frozen_string_literal: true

module Api::Serializer::ActionsLargerRunnersDependency

  include Actions::LargerRunnersHelper

  class UnsupportedImageSource < RuntimeError
    def initialize(source)
      super "Unsupported image source: #{source}"
    end
  end

  def larger_runners_hash(data, options = {})
    {
      total_count: data[:pools].total_entries,
      runners: data[:pools].map do |p|
        pool_image = data[:images].find { |i| i.id == p.image.id && i.source == p.image.source }
        larger_runner_hash({ pool: p, size: p.machine_spec, image: pool_image })
      end
    }
  end

  def larger_runners_machine_specs_hash(data, options = {})
    data ||= []
    machinespecs_hashes = data.map do |ms|
      larger_runner_machine_spec_hash(ms, options)
    end

    {
      total_count: data.count,
      machine_specs: machinespecs_hashes,
    }
  end

  def larger_runner_machine_spec_hash(machine_spec, options = {})
    {
      id: machine_spec.id,
      cpu_cores: machine_spec.cpu_cores,
      memory_gb: machine_spec.memory_gb,
      storage_gb: machine_spec.storage_gb,
    }
  end

  sig { params(data: { images: T::Array[Actions::Image] }, options: T.untyped).returns({ total_count: Integer, images: T::Array[Hash] }) }
  def larger_runners_images_hash(data, options = {})
    images = data.fetch(:images, [])
    images_hashes = images.map do |image|
      larger_runner_image_hash(image, options)
    end

    {
      total_count: images.count,
      images: images_hashes,
    }
  end

  sig { params(image: Actions::Image, options: T.untyped).returns(T.nilable(Hash)) }
  def larger_runner_image_hash(image, options = {})
    if image.nil?
      nil
    else
      { id: image.id, platform: image.platform, size_gb: image.size_gb, display_name: image.display_name, source: larger_runner_image_source(image.source) }
    end
  end

  def larger_runner_image_source(source)
    case source
    when :Curated
      "github"
    when :Marketplace
      "partner"
    when :Custom
      "custom"
    else
      error = UnsupportedImageSource.new(source)
      error.set_backtrace(caller)
      Failbot.report(error, source: source)
    end
  end

  def larger_runner_limits_hash(data, options = {})
    {
      public_ips: {
        current_usage: data[:public_ips][:current_usage],
        maximum: data[:public_ips][:maximum]
      }
    }
  end

  sig { params(data: { platforms: T::Array[String] }, options: T.untyped).returns({ total_count: Integer, platforms: T::Array[String] }) }
  def larger_runner_platforms_hash(data, options = {})
    platforms = data.fetch(:platforms, [])
    {
      total_count: platforms.count,
      platforms: platforms
    }
  end

  def larger_runner_public_ip_hash(public_ip, options = {})
    { enabled: public_ip.enabled, prefix: public_ip.prefix, length: public_ip.length }
  end

  def larger_runner_hash(runner_details, options = {})
    pool = runner_details[:pool]
    public_ips_hash = (pool.public_ips || []).map do |public_ip|
      larger_runner_public_ip_hash(public_ip, options)
    end

    # From backend we can receive 3 "Shutdown" states: ShutdownBilling, ShutdownSpammy, and ShutdownNetwork.
    # But we don't want to show real reason for pool to be in this state, that's why we replace all states with generic "Shutdown"
    pool_state = pool.state&.match("^Shutdown") ? "Shutdown" : pool.state

    {
      id: pool.id,
      name: pool.name,
      image_details: pool.image && runner_details[:image] ? larger_runner_image_hash(runner_details[:image]) : nil,
      runner_group_id: pool.runner_group_id,
      maximum_runners: pool.maximum_runners,
      machine_size_details: larger_runner_machine_spec_hash(runner_details[:size]),
      public_ip_enabled: pool.public_ip_enabled,
      public_ips: public_ips_hash,
      last_active_on: pool.last_active_on,
      status: pool_state
    }
  end
end
