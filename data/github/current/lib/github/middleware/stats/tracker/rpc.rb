# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class Rpc
          extend Tracker

          sig do
            override.params(
              dogstats: T.untyped,
              env: T.untyped,
              stats: T::Hash[Symbol, T.untyped],
              tags_cache: GitHub::DatadogTagsCache,
            ).void
          end
          def self.track(dogstats, env, stats, tags_cache)
            self.track_gitrpc_stats(dogstats, env, stats, tags_cache)
            self.track_memcached_stats(dogstats, env, stats, tags_cache)
            self.track_redis_stats(dogstats, env, stats, tags_cache)
            self.track_es_stats(dogstats, env, stats, tags_cache)
            self.track_authzd_stats(dogstats, env, stats, tags_cache)
            self.track_mysql_stats(dogstats, env, stats, tags_cache)
          end

          def self.rpc_tags(tags_cache)
            # Set of tags to report for request.rpc.dist.queries and request.rpc.dist.time
            # since these are reported 6 times for each request, once for each rpc target.
            # We need to reduce total raw data volume we send to Datadog to reduce cost
            [
              tags_cache[TaggingHelper::METHOD_TAG],
              tags_cache[TaggingHelper::CONTROLLER_TAG],
              tags_cache[TaggingHelper::ACTION_TAG],
              tags_cache[TaggingHelper::CATALOG_SERVICE_TAG],
            ].compact
          end

          def self.track_gitrpc?
            defined?(GitRPCLogSubscriber) && GitRPCLogSubscriber.respond_to?(:rpc_count)
          end

          def self.track_gitrpc_stats(dogstats, env, stats, tags_cache)
            return unless self.track_gitrpc?
            gitrpc_count, gitrpc_time = self.gitrpc_stats
            return unless gitrpc_count > 0

            rpc_tag = "rpc_store:gitrpc"
            dogstats.distribution "request.rpc.dist.queries", gitrpc_count, tags: self.rpc_tags(tags_cache).push(rpc_tag)
            dogstats.distribution "request.rpc.dist.time", gitrpc_time * 1000, tags: self.rpc_tags(tags_cache).push(rpc_tag)
          end

          def self.track_memcached?
            defined?(Memcached::Rails) && Memcached::Rails.respond_to?(:query_count)
          end

          def self.track_memcached_stats(dogstats, env, stats, tags_cache)
            return unless self.track_memcached?
            memcached_count, memcached_time = self.memcached_stats
            return unless memcached_count > 0

            rpc_tag = "rpc_store:memcached"
            dogstats.distribution "request.rpc.dist.queries", memcached_count, tags: self.rpc_tags(tags_cache).push(rpc_tag)
            dogstats.distribution "request.rpc.dist.time", memcached_time * 1000, tags: self.rpc_tags(tags_cache).push(rpc_tag)
          end

          def self.track_redis?
            defined?(::Redis::Client) && ::Redis::Client.respond_to?(:query_count)
          end

          def self.track_redis_stats(dogstats, env, stats, tags_cache)
            return unless self.track_redis?
            redis_count, redis_time = self.redis_stats
            return unless redis_count > 0

            rpc_tag = "rpc_store:redis"
            dogstats.distribution "request.rpc.dist.queries", redis_count, tags: self.rpc_tags(tags_cache).push(rpc_tag)
            dogstats.distribution "request.rpc.dist.time", redis_time * 1000, tags: self.rpc_tags(tags_cache).push(rpc_tag)
          end

          def self.track_es?(elastomer_tracker)
            elastomer_tracker.enabled?
          end

          def self.track_es_stats(dogstats, env, stats, tags_cache)
            elastomer_tracker = Rack::ProcessUtilization::ElastomerTracker.build
            return unless self.track_es?(elastomer_tracker)
            es_count, es_time = self.es_stats(elastomer_tracker)
            return unless es_count > 0

            rpc_tag = "rpc_store:elasticsearch"
            dogstats.distribution "request.rpc.dist.queries", es_count, tags: self.rpc_tags(tags_cache).push(rpc_tag)
            dogstats.distribution "request.rpc.dist.time", es_time * 1000, tags: self.rpc_tags(tags_cache).push(rpc_tag)
          end

          def self.track_authzd?
            defined?(GitHub::AuthzdInstrumenter)
          end

          def self.track_authzd_stats(dogstats, env, stats, tags_cache)
            return unless self.track_authzd?
            authzd_count, authzd_time = self.authzd_stats
            return unless authzd_count > 0

            rpc_tag = "rpc_store:authzd"
            dogstats.distribution "request.rpc.dist.queries", authzd_count, tags: self.rpc_tags(tags_cache).push(rpc_tag)
            dogstats.distribution "request.rpc.dist.time", authzd_time * 1000, tags: self.rpc_tags(tags_cache).push(rpc_tag)
          end

          def self.track_mysql?
            defined?(GitHub::MysqlInstrumenter) && GitHub::MysqlInstrumenter.respond_to?(:query_count)
          end

          def self.track_mysql_stats(dogstats, env, stats, tags_cache)
            return unless self.track_mysql?
            mysql_count, mysql_time = self.mysql_stats
            return unless mysql_count > 0

            rpc_tag = "rpc_store:mysql"
            dogstats.distribution "request.rpc.dist.queries", mysql_count, tags: self.rpc_tags(tags_cache).push(rpc_tag)
            dogstats.distribution "request.rpc.dist.time", mysql_time * 1000, tags: self.rpc_tags(tags_cache).push(rpc_tag)
            GitHub::MysqlInstrumenter.report_stats(stats[:controller], stats[:action], stats[:request_method], stats[:catalog_service], env["action_controller.instance"])
          end

          # MySQL stats for the current request.
          #
          # Returns an Array of
          #   query_count - Number of mysql queries performed
          #   query_time  - A Float time in seconds spent querying
          def self.mysql_stats
            mysql = GitHub::MysqlInstrumenter
            [mysql.query_count, mysql.query_time, mysql.query_counts]
          end

          # GitRPC stats for the current request.
          #
          # Returns an Array of
          #   rpc_count - Number of rpc queries performed
          #   rpc_time  - A Float time in seconds spent querying
          #   rpc_calls - An Array of EventTrace objects
          def self.gitrpc_stats
            [
              GitRPCLogSubscriber.rpc_count,
              GitRPCLogSubscriber.rpc_time,
              GitRPCLogSubscriber.rpc_calls,
            ]
          end

          # Redis stats for current request.
          def self.redis_stats
            redis = ::Redis::Client
            [redis.query_count, redis.query_time, redis.queries]
          end

          # ElasticSearch stats for the current request.
          #
          # Returns an Array of
          #   count - Number of elasticsearch queries performed
          #   time  - Float time in seconds spent querying
          def self.es_stats(elastomer_tracker)
            [elastomer_tracker.count, elastomer_tracker.time / 1000.0]
          end

          # Authzd stats for the current request.
          #
          # Returns an Array of
          #   count - Number of authzd requests executed
          #   time  - Float time in seconds spent querying
          def self.authzd_stats
            [
              GitHub::AuthzdInstrumenter.total_request_count,
              GitHub::AuthzdInstrumenter.total_request_time / 1000.0
            ]
          end

          # Memcached stats for current request.
          def self.memcached_stats
            memcached = Memcached::Rails
            [memcached.query_count, memcached.query_time]
          end
        end
      end
    end
  end
end
