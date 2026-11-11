# typed: strict
# frozen_string_literal: true

require "github/context_caller"

# Internal: Per-request/job tracker for Configuration instances that have been read.
# Implements GH::Context::ScopedData to automatically emit metrics when context exits.
#
# Covers:
# - Rails controller actions
# - API (Sinatra) requests
# - Background jobs (ApplicationJob)
# - Hydro message processors
#
# Note: GitHub.config (the global) is excluded since it persists across requests.
#
# Gated behind the :configsd_read_tracking feature flag.
#
# Logs (0.01% sample rate):
#   GitHub.logger.info("configsd.usage", { config_read_source:, config_read_source_type:, target_type:, target_id:, accessed_keys:, accessed_count:, total_keys:, utilization: })
class Configuration
  class ReadTracker
    include GH::Context::ScopedData

    LOG_SAMPLE_RATE = 0.0001
    CONTEXT_KEY = :config_read_tracker

    sig { void }
    def initialize
      @accessed_keys_by_config = T.let({}, T::Hash[Configuration, T::Set[String]])
    end

    # Track a key read on a Configuration instance.
    sig { params(configuration: Configuration, key: String).void }
    def track(configuration, key)
      keys = @accessed_keys_by_config[configuration] ||= Set.new
      keys << key
    end

    # Returns the set of accessed keys for a Configuration in this context.
    sig { params(configuration: Configuration).returns(T::Set[String]) }
    def accessed_keys_for(configuration)
      @accessed_keys_by_config[configuration] || Set.new
    end

    # Called automatically when GH::Context exits.
    sig { override.void }
    def on_context_exit
      return unless GH.feature_flag_enabled?(:configsd_read_tracking)
      return if @accessed_keys_by_config.empty?
      return unless rand < LOG_SAMPLE_RATE

      source, source_type = source_identifier

      @accessed_keys_by_config.each do |config, accessed|
        total = config.total_keys
        next if total == 0

        GitHub.logger.info("configsd.usage", {
          config_read_source: source,
          config_read_source_type: source_type,
          target_type: config.target.configuration_entry_type,
          target_id: config.target.configuration_entry_id,
          accessed_keys: accessed.to_a,
          accessed_count: accessed.size,
          total_keys: total,
          utilization: accessed.size.to_f / total
        })
      end
    end

    # Register a key read on a Configuration instance in the current context.
    # Creates a new ReadTracker if one doesn't exist for this context.
    sig { params(configuration: Configuration, key: String).void }
    def self.register(configuration, key)
      return unless GH::Context.enabled?

      tracker = T.cast(
        GH.context.data[CONTEXT_KEY] ||= ReadTracker.new,
        ReadTracker
      )
      tracker.track(configuration, key)
    end

    private

    # Determine the source identifier based on context type.
    # Returns [source_name, source_type]
    sig { returns([String, String]) }
    def source_identifier
      GitHub::ContextCaller.identify
    end
  end
end
