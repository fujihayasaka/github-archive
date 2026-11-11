# typed: false
# frozen_string_literal: true

module GitHub
  module Cache
    # Rack middleware to enable and reset the local cache before each request
    # and to release the global reference to the local cache after the response
    # has been returned. Typically set up in config.ru.
    class ResetMiddleware
      attr_accessor :app

      def initialize(app)
        @app = app
      end

      def call(env)
        if GitHub.staff_user_from_env(env)
          GitHub::Cache::Client.distributed_tracing_enabled = true
          if Rack::Request.new(env).GET.has_key?("cache_tracer")
            GitHub::Cache::Client.track_events = true
          end
          if Rack::Request.new(env).GET.has_key?("ff_cache_tracer")
            ::FeatureFlag::Cache::MemcachedClient.track_events = true
          end
        end
        GitHub.cache.enable_local_cache
        app.call(env)
      ensure
        GitHub.dogstats.gauge("cache.local.hit_count", GitHub.cache.local_hit_count, sample_rate: 0.01)
        GitHub.cache.local = nil
        GitHub.cache_partitions.each_value { |cache| cache.skip = nil }
        GitHub::Cache::Client.track_events = false
        ::FeatureFlag::Cache::MemcachedClient.track_events = false
        GitHub::Cache::Client.distributed_tracing_enabled = false
      end
    end
  end
end
