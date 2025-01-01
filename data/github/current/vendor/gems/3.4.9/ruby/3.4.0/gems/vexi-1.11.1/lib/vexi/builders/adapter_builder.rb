# frozen_string_literal: true
#              



require "vexi/configuration"
require "vexi/adapters/file_adapter"
require "vexi/adapters/in_memory_adapter"

module Vexi
  module Builders
    class AdapterBuilder

      def initialize(config)
        @config =      (config               )
      end

      def monolith_optimized_feature_flag_data_from_url(hmac_key, url)
        @config.adapter = Adapters::MonolithOptimizedFeatureFlagDataAdapter.new_from_url(hmac_key, url)
      end

      def monolith_optimized_feature_flag_data_from_connection(conn)
        @config.adapter = Adapters::MonolithOptimizedFeatureFlagDataAdapter.new_from_connection(conn)
      end

      def monolith_optimized_feature_flag_data_from_env(hmac_key)
        @config.adapter = Adapters::MonolithOptimizedFeatureFlagDataAdapter.new_from_env(hmac_key)
      end

      def custom(adapter)
        @config.adapter = adapter
      end

      def in_memory(mode, exception_feature_flags: [])
        default_enabled =      (
          case mode
          when Adapters::InMemoryAdapterMode::DisabledByDefault then false
          when Adapters::InMemoryAdapterMode::EnabledByDefault then true
          else raise ArgumentError, "Invalid mode: #{mode}"
          end            
        )
        adapter_storage = Vexi::FeatureFlagStorage.new(default_enabled: default_enabled, exception_feature_flags: exception_feature_flags)
        @config.adapter = Adapters::InMemoryAdapter.new(shared_storage: adapter_storage)
      end

      def file(feature_flag_base_path, segments_base_path)
        @config.adapter = Adapters::FileAdapter.new(feature_flag_base_path, segments_base_path)
      end
    end
  end
end
