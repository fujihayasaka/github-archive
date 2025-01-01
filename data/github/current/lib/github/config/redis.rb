# typed: false
# frozen_string_literal: true

# Setup global redis objects.
#
# Commands: http://redis.io/commands
require "erb"
require "yaml"
require "redis"
require "redis/distributed"
require "github"
require "disabled_redis"
require "redis-namespace"

module GitHub
  module Config
    # Mixed into the GitHub module
    module Redis

      REDIS_DOWN_EXCEPTIONS = [
        Errno::EAGAIN,
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        Errno::EHOSTUNREACH,
        Errno::ENETUNREACH,
        Errno::EINVAL,
        Timeout::Error,
        # New exception hierarchy since Redis 3.x
        ::Redis::ConnectionError,
        ::Redis::TimeoutError,
        ::Redis::CannotConnectError,
      ]

      # Client side consistent hashing distributed redis implementation.
      #
      # Note that redis.rb does provide `Redis::Distributed` already. However it does not
      # support a master + replicas setup. Making two rings, one with the master instances
      # and one with the replicas leads to different ring setups, meaning certain reads could
      # be routed to shards where the key does not exist.
      #
      # Instead, `DistributedRedis` makes its own `HashRing` using `Redis::HashRing`, and uses
      # that ring to find associated master and replicas for a certain key. Implementing code can
      # then select the master or replicas using the `write` and `read_only` methods.
      #
      # Example:
      #
      #  dist_redis = DistributedRedis.new(master: {...}, replicas: [{...}, {...}])
      #
      #  dist_redis.shard_for("rate_limits:user-12345").write.set("a", 1)
      #
      #  dist_redis.shard_for("rate_limits:user-12345").read_only.get("a")
      #
      class DistributedRedis
        class Shard
          attr_reader :write, :read_only, :id

          def initialize(master_config, replicas_config, idx)
            @write = ::Redis.new(master_config)
            @read_only = ::Redis.new(replicas_config)
            # This ID is used by Redis::HashRing to build a consistent hash ring
            @id = "rate-limiter-redis-#{idx}"
          end
        end

        attr_reader :name

        def initialize(servers, name)
          @shards = servers.map.with_index { |s, i| Shard.new(s[:master], s[:replicas], i) }
          @ring = ::Redis::HashRing.new(@shards)
          @name = name
        end

        def shard_for(key)
          @ring.get_node(key.to_s)
        end

        # Call `flushdb` on each shard on both the master and replicas
        def flushdb
          @ring.nodes.map do |shard|
            shard.write.flushdb
            shard.read_only.flushdb
          end
        end
      end

      # Certain environments may not support a sharded redis setup, in which
      # case we want to keep the same distributed redis API, but always use the same
      # redis instance behind the scenes.
      #
      # `SingleShardDistributedRedis` provides the same interface but always return the redis client
      # it was provided with.
      #
      class SingleShardDistributedRedis
        class Shard
          def initialize(client)
            @client = client
          end

          def write
            @client
          end

          def read_only
            @client
          end
        end

        attr_reader :name

        def initialize(redis, name)
          @shard = Shard.new(redis)
          @name = name
        end

        def shard_for(_key)
          @shard
        end

        def flushdb
          @shard.write.redis.flushdb
        end
      end

      class MockDistributedRedis
        class MockRateLimiterRedis
          def eval(*args)
            [0, nil]
          end

          def evalsha(*args)
            [0, nil]
          end

          def get(key); end

          def del(key); end
        end

        class Shard
          attr_reader :write, :read_only

          def initialize
            @write = MockRateLimiterRedis.new
            @read_only = MockRateLimiterRedis.new
          end
        end

        attr_reader :name

        def initialize
          @shard = MockDistributedRedis::Shard.new
          @name = "mock"
        end

        def shard_for(key)
          @shard
        end

        def flushdb; end
      end

      def simulate_job_coordination_redis_down?
        @simulate_job_coordination_redis_down ||= false
      end
      attr_writer :simulate_job_coordination_redis_down

      def simulate_rate_limiter_redis_down?
        @simulate_rate_limiter_redis_down ||= false
      end
      attr_writer :simulate_rate_limiter_redis_down

      # Public: A client for a redis cluster configured with persistence.
      def job_coordination_redis
        @job_coordination_redis ||= if GitHub.job_coordination_redis_disabled?
          DisabledRedis.new
        else
          ::Redis.new(redis_config)
        end
      end
      attr_writer :job_coordination_redis

      def redis_config
        if GitHub.simulate_job_coordination_redis_down?
          read_redis_config("config/redis-down.yml")
        else
          read_redis_config("config/redis2.yml")
        end
      end

      def rate_limiter_redis
        @rate_limiter_redis ||=
          if GitHub.rate_limiter_redis_disabled?
            SingleShardDistributedRedis.new(DisabledRedis.new, "api")
          elsif GitHub.single_or_multi_tenant_enterprise?
            client = ::Redis::Namespace.new(:rate_limiter, redis: ::Redis.new(read_redis_config("config/redis2.yml")))
            SingleShardDistributedRedis.new(client, "api")
          else
            DistributedRedis.new(read_distributed_redis_config("config/redis_rate_limiter.yml"), "api")
          end
      end
      attr_writer :rate_limiter_redis

      def mock_monolith_rate_limiter_redis!
        unless GitHub::AppEnvironment.test? || GitHub::AppEnvironment.development?
          raise StandardError, "GitHub rate limiter redis should not be mocked in this environment."
        end
        GitHub.monolith_rate_limiter_redis = MockDistributedRedis.new
      end

      def monolith_rate_limiter_redis
        @monolith_rate_limiter_redis ||=
          if GitHub.rate_limiter_redis_disabled?
            SingleShardDistributedRedis.new(DisabledRedis.new, "monolith")
          elsif GitHub.single_or_multi_tenant_enterprise?
            client = ::Redis::Namespace.new(:rate_limiter, redis: ::Redis.new(read_redis_config("config/redis2.yml")))
            SingleShardDistributedRedis.new(client, "monolith")
          else
            DistributedRedis.new(read_distributed_redis_config("config/monolith_redis_rate_limiter.yml"), "monolith")
          end
      end
      attr_writer :monolith_rate_limiter_redis

      def read_distributed_redis_config(file)
        file   = "#{GitHub::AppEnvironment.root}/#{file}" unless file[0..0] == "/"
        data   = ERB.new(File.read(file)).result
        servers    = YAML.load(data)[GitHub::AppEnvironment.env]["servers"]

        servers.map do |server|
          master_config = merge_redis_config(url: server["master"])
          replicas_config = merge_redis_config(url: server["replicas"])

          if password = server["password"]
            master_config = master_config.merge(password: password)
            replicas_config = replicas_config.merge(password: password)
          end

          { master: master_config, replicas: replicas_config }
        end
      end

      def read_redis_config(file, connect_timeout: nil)
        file = "#{GitHub::AppEnvironment.root}/#{file}"
        data = ERB.new(File.read(file)).result
        config = YAML.load(data)
        url = config[GitHub::AppEnvironment.env]
        timeout = config["timeout"]

        merge_redis_config(url: url, timeout: timeout, connect_timeout: connect_timeout)
      end

      def merge_redis_config(url:, timeout: nil, connect_timeout: nil)
        # Limit redis operations to 2 seconds in dotcom. The default configuration allows
        # for a single retry, effectively making this a 4 second timeout. This
        # leaves 6 additional seconds in the 10-second request timeout for
        # recovery and other processing in case redis is timing out or
        # unavailable.
        #
        # Allow the timeout to be overridden in enterprise to support slower operations
        # like migrations that happen outside of requests.
        timeout = if GitHub.enterprise? && timeout.present?
          timeout
        else
          2.0
        end

        config = { thread_safe: true, timeout: timeout }

        # The timeout is increased for review lab to give the cpu-limited redis
        # pod a longer chance to respond.
        if GitHub.dynamic_lab?
          config[:connect_timeout] = 5.0
        end

        if connect_timeout
          config[:connect_timeout] = connect_timeout
        end

        if url =~ %r{^redis(s)?://}
          config.merge(url: url, ssl_params: { ca_file: "/etc/ssl/certs/ca-certificates.crt" })
        else
          host, port, db = url.split(":")
          config.merge(host: host, port: port, db: db)
        end
      end
    end
  end

  extend Config::Redis
end
