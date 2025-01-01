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
            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

            self.track_gitrpc_stats(dogstats, env, stats, tags_cache)
            gitrpc_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

            self.track_spokesd_stats(dogstats, env, stats, tags_cache)
            spokesd_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

            self.track_memcached_stats(dogstats, env, stats, tags_cache)
            memcached_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

            self.track_redis_stats(dogstats, env, stats, tags_cache)
            redis_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

            self.track_es_stats(dogstats, env, stats, tags_cache)
            es_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

            self.track_authzd_stats(dogstats, env, stats, tags_cache)
            authzd_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

            self.track_mysql_stats(dogstats, env, stats, tags_cache)
            mysql_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

            segment_duration_gitrpc = (gitrpc_time - start_time) * 1_000_000
            segment_duration_spokesd = (spokesd_time - gitrpc_time) * 1_000_000
            segment_duration_memcached = (memcached_time - spokesd_time) * 1_000_000
            segment_duration_redis = (redis_time - memcached_time) * 1_000_000
            segment_duration_es = (es_time - redis_time) * 1_000_000
            segment_duration_authzd = (authzd_time - es_time) * 1_000_000
            segment_duration_mysql = (mysql_time - authzd_time) * 1_000_000

            dogstats.distribution("request.dist.stats_tracker_time.rpc", segment_duration_gitrpc, tags: ["segment:gitrpc"])
            dogstats.distribution("request.dist.stats_tracker_time.rpc", segment_duration_spokesd, tags: ["segment:spokesd"])
            dogstats.distribution("request.dist.stats_tracker_time.rpc", segment_duration_memcached, tags: ["segment:memcached"])
            dogstats.distribution("request.dist.stats_tracker_time.rpc", segment_duration_redis, tags: ["segment:redis"])
            dogstats.distribution("request.dist.stats_tracker_time.rpc", segment_duration_es, tags: ["segment:es"])
            dogstats.distribution("request.dist.stats_tracker_time.rpc", segment_duration_authzd, tags: ["segment:authzd"])
            dogstats.distribution("request.dist.stats_tracker_time.rpc", segment_duration_mysql, tags: ["segment:mysql"])
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
              tags_cache[TaggingHelper::LOGGED_IN_TAG],
            ].compact
          end

          def self.track_gitrpc?
            defined?(GitRPCLogSubscriber) && GitRPCLogSubscriber.respond_to?(:rpc_count)
          end

          def self.track_gitrpc_stats(dogstats, env, stats, tags_cache)
            return unless self.track_gitrpc?
            gitrpc_count, gitrpc_time = self.gitrpc_stats
            return unless gitrpc_count > 0

            tags = self.rpc_tags(tags_cache).push("rpc_store:gitrpc")
            dogstats.distribution("request.rpc.dist.queries", gitrpc_count, tags: tags)
            dogstats.distribution("request.rpc.dist.time", gitrpc_time * 1000, tags: tags)
          end

          def self.track_spokesd?
            defined?(GitHub::DataCollector::SpokesdInstrumenterCollector) && \
              GitHub::DataCollector::SpokesdInstrumenterCollector.get_instance.enabled?
          end

          def self.track_spokesd_stats(dogstats, env, stats, tags_cache)
            return unless self.track_spokesd?
            spokesd_count, spokesd_time = self.spokesd_stats

            return unless spokesd_count > 0

            rpc_tag = "rpc_store:spokesd"
            dogstats.distribution "request.rpc.dist.queries", spokesd_count, tags: self.rpc_tags(tags_cache) + [rpc_tag]
            dogstats.distribution "request.rpc.dist.time", spokesd_time, tags: self.rpc_tags(tags_cache) + [rpc_tag]
          end

          def self.track_memcached?
            defined?(Memcached::Rails) && Memcached::Rails.respond_to?(:query_count)
          end

          def self.track_memcached_stats(dogstats, env, stats, tags_cache)
            return unless self.track_memcached?
            memcached_count, memcached_time = self.memcached_stats
            return unless memcached_count > 0

            tags = self.rpc_tags(tags_cache).push("rpc_store:memcached")
            dogstats.distribution("request.rpc.dist.queries", memcached_count, tags: tags)
            dogstats.distribution("request.rpc.dist.time", memcached_time * 1000, tags: tags)
          end

          def self.track_redis?
            defined?(::Redis::Client) && ::Redis::Client.respond_to?(:query_count)
          end

          def self.track_redis_stats(dogstats, env, stats, tags_cache)
            return unless self.track_redis?
            redis_count, redis_time = self.redis_stats
            return unless redis_count > 0

            tags = self.rpc_tags(tags_cache).push("rpc_store:redis")
            dogstats.distribution("request.rpc.dist.queries", redis_count, tags: tags)
            dogstats.distribution("request.rpc.dist.time", redis_time * 1000, tags: tags)
          end

          def self.track_es?(elastomer_tracker)
            elastomer_tracker.enabled?
          end

          def self.track_es_stats(dogstats, env, stats, tags_cache)
            elastomer_tracker = Rack::ProcessUtilization::ElastomerTracker.build
            return unless self.track_es?(elastomer_tracker)
            es_count, es_time = self.es_stats(elastomer_tracker)
            return unless es_count > 0

            tags = self.rpc_tags(tags_cache).push("rpc_store:elasticsearch")
            dogstats.distribution("request.rpc.dist.queries", es_count, tags: tags)
            dogstats.distribution("request.rpc.dist.time", es_time * 1000, tags: tags)
          end

          def self.track_authzd?
            defined?(GitHub::AuthzdInstrumenter)
          end

          def self.track_authzd_stats(dogstats, env, stats, tags_cache)
            return unless self.track_authzd?
            authzd_count, authzd_time = self.authzd_stats
            return unless authzd_count > 0

            tags = self.rpc_tags(tags_cache).push("rpc_store:authzd")
            dogstats.distribution("request.rpc.dist.queries", authzd_count, tags: tags)
            dogstats.distribution("request.rpc.dist.time", authzd_time * 1000, tags: tags)
          end

          def self.track_mysql?
            defined?(GitHub::MysqlInstrumenter) && GitHub::MysqlInstrumenter.respond_to?(:query_count)
          end

          def self.track_mysql_stats(dogstats, env, stats, tags_cache)
            return unless self.track_mysql?
            mysql_count, mysql_time = self.mysql_stats
            return unless mysql_count > 0

            tags = self.rpc_tags(tags_cache).push("rpc_store:mysql")
            dogstats.distribution("request.rpc.dist.queries", mysql_count, tags: tags)
            dogstats.distribution("request.rpc.dist.time", mysql_time * 1000, tags: tags)
            GitHub::MysqlInstrumenter.report_stats(
              stats[:controller],
              stats[:action],
              stats[:request_method],
              stats[:catalog_service],
              env["action_controller.instance"],
              GitHub::TaggingHelper.rest_api_read_from_replicas?(env),
              tags_cache
            )
          end

          # MySQL stats for the current request.
          #
          # Returns an Array of
          #   query_count - Number of mysql queries performed
          #   query_time  - A Float time in seconds spent querying
          def self.mysql_stats
            [GitHub::MysqlInstrumenter.query_count, GitHub::MysqlInstrumenter.query_time]
          end

          # GitRPC stats for the current request.
          #
          # Returns an Array of
          #   rpc_count - Number of rpc queries performed
          #   rpc_time  - A Float time in seconds spent querying
          def self.gitrpc_stats
            [GitRPCLogSubscriber.rpc_count, GitRPCLogSubscriber.rpc_time]
          end

          def self.spokesd_stats
            [
              GitHub::DataCollector::SpokesdInstrumenterCollector.get_instance.rpc_count,
              GitHub::DataCollector::SpokesdInstrumenterCollector.get_instance.rpc_time,
            ]
          end

          # Redis stats for current request.
          def self.redis_stats
            [::Redis::Client.query_count, ::Redis::Client.query_time]
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
            [GitHub::AuthzdInstrumenter.total_request_count, GitHub::AuthzdInstrumenter.total_request_time / 1000.0]
          end

          # Memcached stats for current request.
          def self.memcached_stats
            [Memcached::Rails.query_count, Memcached::Rails.query_time]
          end
        end
      end
    end
  end
end
