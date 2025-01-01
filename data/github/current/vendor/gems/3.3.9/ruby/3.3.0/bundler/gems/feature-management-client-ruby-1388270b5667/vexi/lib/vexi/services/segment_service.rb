# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"
require "fnv"
require "vexi/abstract_entity_service"
require "vexi/models/get_entity_response"

module Vexi
  # Public: Vexi services.
  module Services
    # Public: Segment service responsible for fetching segments from the cache or the adapter.
    class SegmentService < AbstractEntityService
      extend T::Generic # Provides `type_member` helper

      EntityType = type_member { { fixed: Segment } }

      def initialize(adapter, cache_config = nil, adapter_breaker = nil, cache_breaker = nil)
        super(adapter, cache_config, adapter_breaker, cache_breaker)
        @cache_key_prefix = T.let(cache_config&.segment_key_prefix || CacheConfig::DEFAULT_SEGMENT_KEY_PREFIX, String)
      end

      def entity_type
        Segment
      end

      def entity_type_name
        "segment"
      end

      def get_cache_key(name)
        "#{@cache_key_prefix}#{name}"
      end

      def get_entity_responses(names);
        @adapter.get_segments(names)
      end

      def get_default_entity_instance(name)
        Segment.create_default(name)
      end
    end
  end
end
