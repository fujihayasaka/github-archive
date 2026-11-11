# frozen_string_literal: true
#              


require "vexi/builder"
require "vexi/client"
require "vexi/configuration"
require "vexi/services/feature_flag_service"
require "vexi/services/segment_service"

# Public: The main Vexi module for performing feature flag enabled checks.
module Vexi
  extend T::Sig

  @config_version =      (nil                  )

  # Public: The main Vexi class for performing feature flag enabled checks.

  # Public: This method can be used to simply configure and create a new vexi instance
  #         The returned client is not storead in a thread-safe way so it is generally
  #         recommended to use `configure()` followed by `instance()` instead.
  def self.build(&blk)
    config = Configuration.new
    builder = Builder.new(config)

    blk.call(builder)

    config.create_instance
  end

  # Public: Configure Vexi
  def self.configure(&blk)
    # Reset config and before configuring the client again
    @configuration = Configuration.new
    builder = Builder.new(configuration)

    blk.call(builder)

    @config_version =      (Time.now.to_f                  )
    Thread.current[:vexi_config_version] = @config_version
    Thread.current[:vexi_instance] = configuration.create_instance
  end

  # Public: Get the vexi instance for the currently running thread, requires the Vexi to be configured first
  def self.instance
    current_thread_version = Thread.current[:vexi_config_version]
    if current_thread_version.nil? || @config_version.nil? || current_thread_version != @config_version
      # If configure has been called in another thread, we need to reset the instance being used
      Thread.current[:vexi_instance] = configuration.create_instance
      Thread.current[:vexi_config_version] = @config_version || Time.now.to_f
    end
    Thread.current[:vexi_instance]
  end

  def self.configuration
    @configuration ||=      (Configuration.new                                  )
  end
end
