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
      # Circuit breaker cluster names - MUST be unique to prevent coupling
      CLUSTER_MONOLITH = "monolith"
      CLUSTER_API = "api"
      CLUSTER_MOCK = "mock"

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

      # default timeout and connect timeout for redis client in seconds
      DEFAULT_TIMEOUT = 2.0

      # default reconnect timeout in seconds (target: 200ms)
      DEFAULT_RECONNECT_TIMEOUT = 0.2

      # Calculate maximum reconnect timeout based on connection timeout
      # Returns a reasonable maximum that's a fraction of the connection timeout
      # to ensure reconnect attempts remain effective
      def max_reconnect_timeout_for(timeout)
        # Cap at 50% of the timeout to leave room for the actual connection attempt
        # With a minimum of 10% of DEFAULT_TIMEOUT and maximum of 50% of DEFAULT_TIMEOUT for reasonable bounds
        calculated_max = timeout * 0.5
        min_bound = DEFAULT_TIMEOUT * 0.1  # 10% of default timeout (0.2s)
        max_bound = DEFAULT_TIMEOUT * 0.5  # 50% of default timeout (1.0s)
        [min_bound, [calculated_max, max_bound].min].max
      end

      # Generate a per-instance jittered reconnect timeout
      # This ensures each application instance has a slightly different reconnect timeout
      # to prevent thundering herd during connection retry storms
      #
      # base_delay - Float representing the base delay value (in seconds) for the single retry attempt
      # timeout - Float representing the connection timeout to calculate appropriate maximum (default: DEFAULT_TIMEOUT)
      #
      # Returns an array with a single jittered delay that's consistent for this instance
      # The delay is capped based on the connection timeout to ensure reconnect attempts remain effective
      def generate_reconnect_jitter(base_delay, timeout = DEFAULT_TIMEOUT)
        return base_delay unless base_delay.is_a?(Numeric)

        # Allow configurable jitter factor via environment variable, default to 10%
        jitter_factor = ENV.fetch("REDIS_RATE_LIMITER_RECONNECT_JITTER_FACTOR", "0.1").to_f

        # Generate a per-instance jittered timeout that's consistent across calls
        # This prevents all instances from having the same reconnect timing
        @instance_reconnect_jitter ||= {}
        cache_key = "#{base_delay}_#{jitter_factor}_#{timeout}"

        @instance_reconnect_jitter[cache_key] ||= begin
          # Add random jitter: delay ± (delay * jitter_factor)
          jitter = base_delay * jitter_factor * (rand * 2 - 1) # Random between -jitter_factor and +jitter_factor
          jittered_delay = base_delay + jitter

          # Ensure delay is never negative, use a minimum jitter value if it would be zero or negative
          if jittered_delay <= 0.0
            jittered_delay = DEFAULT_RECONNECT_TIMEOUT * jitter_factor * rand
          end

          # Cap the maximum delay based on the connection timeout to ensure effectiveness
          max_timeout = max_reconnect_timeout_for(timeout)
          jittered_delay = [jittered_delay, max_timeout].min

          # Return as array with single element for reconnect_attempts configuration
          [jittered_delay]
        end
      end

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

          def initialize(master_config, replicas_config, idx, cluster_name)
            @write = ::Redis.new(master_config)
            @read_only = ::Redis.new(replicas_config)
            # This ID is used by Redis::HashRing to build a consistent hash ring
            # Include cluster_name to ensure different Redis infrastructures have separate circuit breakers
            @id = "#{cluster_name}-rate-limiter-redis-#{idx}"
          end
        end

        attr_reader :name

        def initialize(servers, name)
          @shards = servers.map.with_index { |s, i| Shard.new(s[:master], s[:replicas], i, name) }
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
          attr_reader :id

          def initialize(client, cluster_name)
            @client = client
            # Provide a consistent ID for circuit breaker purposes
            # Include cluster_name to ensure different Redis infrastructures have separate circuit breakers
            @id = "#{cluster_name}-single-shard-redis"
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
          @shard = Shard.new(redis, name)
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
          attr_reader :write, :read_only, :id

          def initialize(cluster_name)
            @write = MockRateLimiterRedis.new
            @read_only = MockRateLimiterRedis.new
            # Provide a consistent ID for circuit breaker purposes
            # Include cluster_name to ensure different Redis infrastructures have separate circuit breakers
            @id = "#{cluster_name}-mock-redis"
          end
        end

        attr_reader :name

        def initialize(cluster_name = CLUSTER_MOCK)
          @shard = MockDistributedRedis::Shard.new(cluster_name)
          @name = cluster_name
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
      #
      # Note: In Proxima/Enterprise, this client and new_job_coord_redis point to the same redis cluster.
      #       As such, care should be taken to namespace keys for your feature to avoid collisions.
      def legacy_redis
        @legacy_redis ||= if GitHub.job_coordination_redis_disabled?
          DisabledRedis.new
        else
          config = redis_config
          config[:custom] = { trace_command_size: true }
          ::Redis.new(config)
        end
      end
      attr_writer :legacy_redis

      # Note: In Proxima/Enterprise, this client and legacy_redis point to the same redis cluster.
      #       As such, care should be taken to namespace keys for your feature to avoid collisions.
      #
      # TODO: https://github.com/github/monolith-systems/issues/408
      #       rename this once job locking is migrated here
      def new_job_coord_redis
        @new_job_coord_redis ||= if GitHub.job_coordination_redis_disabled?
          DisabledRedis.new
        elsif GitHub.single_or_multi_tenant_enterprise?
          ::Redis.new(read_redis_config("config/redis2.yml"))
        else
          ::Redis::Distributed.new(read_distributed_redis_config("config/redis_job_coord.yml"))
        end
      end
      attr_writer :new_job_coord_redis

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
            SingleShardDistributedRedis.new(DisabledRedis.new, CLUSTER_API)
          elsif GitHub.single_or_multi_tenant_enterprise?
            client = ::Redis::Namespace.new(:rate_limiter, redis: ::Redis.new(read_redis_config("config/redis2.yml")))
            SingleShardDistributedRedis.new(client, CLUSTER_API)
          else
            DistributedRedis.new(read_replicated_redis_config("config/redis_rate_limiter.yml"), CLUSTER_API)
          end
      end
      attr_writer :rate_limiter_redis

      def mock_monolith_rate_limiter_redis!
        unless GitHub::AppEnvironment.test? || GitHub::AppEnvironment.development?
          raise StandardError, "GitHub rate limiter redis should not be mocked in this environment."
        end
        GitHub.monolith_rate_limiter_redis = MockDistributedRedis.new(CLUSTER_MONOLITH)
      end

      def monolith_rate_limiter_redis
        @monolith_rate_limiter_redis ||=
          if GitHub.rate_limiter_redis_disabled?
            SingleShardDistributedRedis.new(DisabledRedis.new, CLUSTER_MONOLITH)
          elsif GitHub.single_or_multi_tenant_enterprise?
            client = ::Redis::Namespace.new(:rate_limiter, redis: ::Redis.new(read_redis_config("config/redis2.yml")))
            SingleShardDistributedRedis.new(client, CLUSTER_MONOLITH)
          else
            DistributedRedis.new(read_replicated_redis_config("config/monolith_redis_rate_limiter.yml"), CLUSTER_MONOLITH)
          end
      end
      attr_writer :monolith_rate_limiter_redis

      def read_distributed_redis_config(file)
        file   = "#{GitHub::AppEnvironment.root}/#{file}" unless file[0..0] == "/"
        data   = ERB.new(File.read(file)).result
        config = YAML.load(data)[GitHub::AppEnvironment.env]
        servers = config["servers"]
        timeout = config["timeout"] || DEFAULT_TIMEOUT
        reconnect_timeout = config["reconnect_timeout"]
        connect_timeout = config["connect_timeout"] || timeout
        read_timeout = config["read_timeout"] || timeout
        write_timeout = config["write_timeout"] || timeout

        servers.map do |url|
          node_config = merge_redis_config(url: url, timeout: timeout, reconnect_timeout: reconnect_timeout, read_timeout: read_timeout, write_timeout: write_timeout, connect_timeout: connect_timeout)
        end
      end

      def read_replicated_redis_config(file)
        file   = "#{GitHub::AppEnvironment.root}/#{file}" unless file[0..0] == "/"
        data   = ERB.new(File.read(file)).result
        config = YAML.load(data)[GitHub::AppEnvironment.env]
        servers = config["servers"]

        timeout = config["timeout"] || DEFAULT_TIMEOUT
        reconnect_timeout = config["reconnect_timeout"]
        connect_timeout = config["connect_timeout"] || timeout
        read_timeout = config["read_timeout"] || timeout
        write_timeout = config["write_timeout"] || timeout

        servers.map do |server|
          master_config = merge_redis_config(url: server["master"], timeout: timeout, reconnect_timeout: reconnect_timeout, read_timeout: read_timeout, write_timeout: write_timeout, connect_timeout: connect_timeout)
          replicas_config = merge_redis_config(url: server["replicas"], timeout: timeout, reconnect_timeout: reconnect_timeout, read_timeout: read_timeout, write_timeout: write_timeout, connect_timeout: connect_timeout)

          if password = server["password"]
            master_config = master_config.merge(password: password)
            replicas_config = replicas_config.merge(password: password)
          end

          { master: master_config, replicas: replicas_config }
        end
      end

      def read_redis_config(file, connect_timeout: nil, read_timeout: nil)
        file = "#{GitHub::AppEnvironment.root}/#{file}"
        data = ERB.new(File.read(file)).result
        config = YAML.load(data)
        url = config[GitHub::AppEnvironment.env]
        timeout = config["timeout"]
        connect_timeout ||= config["connect_timeout"]
        reconnect_timeout = config["reconnect_timeout"]
        read_timeout ||= config["read_timeout"] || timeout
        write_timeout = config["write_timeout"] || timeout

        merge_redis_config(url: url, timeout: timeout, connect_timeout: connect_timeout, reconnect_timeout: reconnect_timeout, read_timeout: read_timeout, write_timeout: write_timeout)
      end

      def merge_redis_config(url:, timeout: nil, connect_timeout: nil, reconnect_timeout: nil, read_timeout: nil, write_timeout: nil)
        # Limit redis operations to default timeout if not specified. The default configuration
        # allows for a single retry, effectively making this a 2xDEFAULT_TIMEOUT second timeout.
        # This leaves additional time in the 10-second request timeout for recovery and other processing
        # in case redis is timing out or unavailable.
        # Do not set this value too high, as it is added to response latency
        timeout = DEFAULT_TIMEOUT if timeout.nil?

        config = {
          connect_timeout: connect_timeout || timeout,
          read_timeout: read_timeout || timeout,
          write_timeout: write_timeout || timeout,
        }

        # The timeout is increased for review lab to give the cpu-limited redis
        # pod a longer chance to respond.
        if GitHub.dynamic_lab?
          config[:connect_timeout] = 5.0
        end

        # Add reconnect_attempts with jitter if reconnect_timeout is specified
        # Uses a single reconnect attempt with jittered timing
        if reconnect_timeout
          # Use connect_timeout if available, otherwise fall back to timeout
          effective_timeout = connect_timeout || timeout
          config[:reconnect_attempts] = generate_reconnect_jitter(reconnect_timeout, effective_timeout)
        end

        if url =~ %r{^redis(s)?://}
          config.merge(url: url, ssl_params: { ca_file: "/etc/ssl/certs/ca-certificates.crt" })
        else
          host, port, db = url.split(":")
          config.merge(host: host, port: port, db: db)
        end
      end

      sig { returns(Float) }
      attr_accessor :redis_instrumentation_pipeline_stats_sample_rate

      sig { returns(Float) }
      attr_accessor :redis_instrumentation_connect_stats_sample_rate
    end
  end

  extend Config::Redis
end

class RedisClient
  class RubyConnection
    # redis-rb < 5.0 allowed configuring tcp_keepalive via the `:tcp_keepalive` option.
    # We did not previously enable it, so patching this to maintain consistency until we rule out problems
    #
    # This works by overriding the `enable_socket_keep_alive` method to do nothing.
    # see: https://github.com/redis-rb/redis-client/blob/v0.24.0/lib/redis_client/ruby_connection.rb#L169-L189
    #
    # Which matches the early return behavior of redis-rb@4.8.1
    # see: https://github.com/redis/redis-rb/blob/v4.8.1/lib/redis/connection/ruby.rb#L321
    #      https://github.com/redis/redis-rb/blob/v4.8.1/lib/redis/client.rb#L25
    #      https://github.com/redis/redis-rb/blob/v4.8.1/lib/redis/client.rb#L512-L522
    #
    # We can revisit this later
    def enable_socket_keep_alive(_socket)
    end
  end
end
