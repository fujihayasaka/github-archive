# typed: true
# frozen_string_literal: true

module GitHub
  # Appends Server-Timing headers to the response for viewing in browser
  # network devtools.
  #
  # https://w3c.github.io/server-timing/
  class ServerTimingMiddleware
    ENABLE_KEY = "github.rack.server_timing_enabled"

    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)
      stats = env[Rack::ProcessUtilization::ENV_KEY]
      if stats && enabled?(env)
        value = timings(stats, env)
        if !value.empty?
          headers["Server-Timing"] = value
        end
      end
      [status, headers, body]
    end

    private

    def timings(stats, env)
      values = []
      if stats.track_mysql?
        values << ["SQL", stats.mysql_stats[1]]
      end
      if stats.track_redis?
        values << ["Redis", stats.redis_stats[1]]
      end
      if stats.track_graphql?
        values << ["GraphQL", stats.graphql_stats[1]]
      end
      if stats.track_cache?
        values << ["Cache", stats.cache_stats[1]]
      end
      if stats.track_gc?
        values << ["GC", stats.gc_info.time]
      end
      if stats.track_es?
        values << ["Search", stats.es_stats[1]]
      end
      if stats.track_gitrpc?
        values << ["GitRPC", stats.gitrpc_stats[1]]
      end
      if stats.track_render? && stats.render_stats
        values << ["Render", stats.render_stats.total_time]
      end
      if alloy_wait_time = env[GitHub::TaggingHelper::ALLOY_WAIT_TIME]
        values << ["SSR", alloy_wait_time]
      end
      if stats.track_cpu?
        cpu, idle, real = stats.cpu_stats
        values << ["Unicorn", cpu + idle]
      end
      if glb_wait_time = env[GitHub::TaggingHelper::GLB_WAIT_TIME]
        values << ["GLB", glb_wait_time]
      end
      if nginx_queued_time = env[GitHub::TaggingHelper::REQ_WAIT_TIME]
        values << ["Nginx", nginx_queued_time]
      end
      values.map { |name, value| "#{name};dur=#{millis(value)}" }.join(",")
    end

    def millis(duration)
      (duration * 1000).round(2)
    end

    def enabled?(env)
      GitHub.staff_user_from_env(env) || env[ENABLE_KEY]
    end
  end
end
