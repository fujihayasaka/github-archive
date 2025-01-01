# typed: true
# frozen_string_literal: true

module Flipper
  module Adapters
    class Memcacheable
      include ::Flipper::Adapter

      FEATURES_KEY = "flipper_features".freeze
      FEATURE_KEY_PREFIX = "flipper_feature:".freeze
      TTL = 30 # seconds

      def self.key_for(feature_key)
        "#{FEATURE_KEY_PREFIX}#{feature_key}"
      end

      def self.key_for_actor(feature_key, actor_id)
        "flipper_feature_actor:#{feature_key}:#{actor_id}"
      end

      attr_reader :name

      # Public
      def initialize(adapter, cache)
        @name = :memcacheable
        @adapter = adapter
        @cache = cache
      end

      # Public
      def features
        fetch(FEATURES_KEY, tags: ["caller:features"]) do
          @adapter.features
        end
      end

      # Public
      def add(feature)
        result = @adapter.add(feature)

        cache.delete(FEATURES_KEY)

        result
      end

      # Public
      def remove(feature)
        result = @adapter.remove(feature)

        cache.delete(FEATURES_KEY)
        cache.delete(feature_key(feature))

        result
      end

      # Public
      def clear(feature)
        result = @adapter.clear(feature)

        cache.delete(feature_key(feature))

        result
      end

      # Public
      def get(feature)
        fetch(feature_key(feature), tags: ["caller:get"]) do
          @adapter.get(feature)
        end
      end

      def get_multi(features)
        keys = features.map { |feature| feature_key(feature) }

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = cache.get_multi(keys)
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

        uncached_features = features.reject { |feature| result[feature_key(feature)] }

        duration_tags = ["cache_hit_count:#{keys.size - uncached_features.size}"]
        GitHub.dogstats.distribution("flipper.adapter.memcache.get_multi.duration", duration, tags: duration_tags)

        # Fire flipper.adapter.memcache.hit and flipper.adapter.memcache.miss metrics
        keys.each do |key|
          if result[key]
            GitHub.dogstats.increment("flipper.adapter.memcache.hit", tags: ["caller:get_multi"])
          else
            GitHub.dogstats.increment("flipper.adapter.memcache.miss", tags: ["caller:get_multi"])
          end
        end

        if uncached_features.any?
          response = @adapter.get_multi(uncached_features)
          response.each do |key, value|
            cache.set(key_for(key), value, TTL)
            result[key] = value
          end
        end

        result.to_h do |key, feature_flag_config|
          [
            key.sub(FEATURE_KEY_PREFIX, ""),
            feature_flag_config
          ]
        end
      end

      # Public
      def enable(feature, gate, thing)
        result = @adapter.enable(feature, gate, thing)

        cache.delete(feature_key(feature)) if GitHub.flippers_should_clear_actor_cache || gate.name != :actor

        if GitHub.flippers_should_clear_actor_cache && gate.name == :actor
          cache.delete(key_for_actor(feature.key, thing.value))
        end
        result
      end

      # Public
      def disable(feature, gate, thing)
        result = @adapter.disable(feature, gate, thing)

        cache.delete(feature_key(feature)) if GitHub.flippers_should_clear_actor_cache || gate.name != :actor

        if GitHub.flippers_should_clear_actor_cache && gate.name == :actor
          cache.delete(key_for_actor(feature.key, thing.value))
        end
        result
      end

      # Public. Look up a feature value for the given actor.
      def feature_enabled?(feature_key, actor_id)
        # wrap the cached value in an array to avoid any weirdness
        # related to checking if 'false' is cached.
        result = fetch(key_for_actor(feature_key, actor_id), tags: ["caller:feature_enabled"]) do
          [@adapter.feature_enabled?(feature_key, actor_id)]
        end
        result.first
      end

      # Public.
      def actors_value(feature_key)
        @adapter.actors_value(feature_key)
      end

      def feature_key(feature)
        key_for(feature.key)
      end

      def key_for_actor(feature_key, actor_id)
        self.class.key_for_actor(feature_key, actor_id)
      end

      def key_for(feature_key)
        self.class.key_for(feature_key)
      end

      private

      attr_reader :cache

      def fetch(cache_key, tags: [])
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = cache.get(cache_key)
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

        if result.nil?
          GitHub.dogstats.increment("flipper.adapter.memcache.miss", tags: tags)
          tags << "cache_hit:false"
          result = yield
          cache.set(cache_key, result, TTL)
        else
          GitHub.dogstats.increment("flipper.adapter.memcache.hit", tags: tags)
          tags << "cache_hit:true"
        end

        GitHub.dogstats.distribution("flipper.adapter.memcache.duration", duration, tags: tags)

        result
      end
    end
  end
end
