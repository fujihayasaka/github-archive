# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"
require "vexi/models/get_entity_response"

module Vexi
  # Public: Vexi services.
  module Services
    # Public: Feature Flag Service responsible for fetching feature flags from the cache or adapter.
    class FeatureFlagService < AbstractEntityService
      extend T::Generic # Provides `type_member` helper

      EntityType = type_member { { fixed: FeatureFlag } }

      def initialize(adapter, cache_config = nil, adapter_breaker = nil, cache_breaker = nil)
        super(adapter, cache_config, adapter_breaker, cache_breaker)
        @cache_key_prefix = T.let(cache_config&.feature_flag_key_prefix || CacheConfig::DEFAULT_FEATURE_FLAG_KEY_PREFIX, String)
      end

      def entity_type
        FeatureFlag
      end

      def entity_type_name
        "feature_flag"
      end

      def get_cache_key(name)
        "#{@cache_key_prefix}#{name}"
      end

      def get_entity_responses(names);
        @adapter.get_feature_flags(names)
      end

      def get_default_entity_instance(name)
        FeatureFlag.create_default(name)
      end
    end
  end
end
