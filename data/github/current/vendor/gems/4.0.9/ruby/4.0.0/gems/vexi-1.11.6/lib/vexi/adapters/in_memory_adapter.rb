# frozen_string_literal: true
#              


require "vexi/adapter"
require "vexi/models/feature_flag_storage"

module Vexi
  module Adapters
    # Public: In memory adapter mode enum
    # This is being used by the AdapterBuilder and kept around for public interface compatibility
    class InMemoryAdapterMode
      DisabledByDefault = 0
      EnabledByDefault = 1
    end

    # Public: In memory adapter for Vexi.
    class InMemoryAdapter
      include Adapter

      def initialize(shared_storage: FeatureFlagStorage.new)
        @shared_storage =      (shared_storage                    )
      end

      def features
        @shared_storage.values
      end

      def get_feature_flags(names)
        feature_flags = []
        names.each do |name|
          # Prevent unexpected results for situations where reading a feature flag would save it to storage when it doesn't exist
          feature_flag = @shared_storage.get_or_build(name)
          feature_flags << GetFeatureFlagResponse.new(
            name: name,
            feature_flag: feature_flag
          )
        end
        feature_flags
      end

      def get_segments(_names)
        []
      end

      def adapter_name
        "in_memory"
      end
    end
  end
end
