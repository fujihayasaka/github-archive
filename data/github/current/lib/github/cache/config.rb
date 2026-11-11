# typed: true
# frozen_string_literal: true

require "erb"

module GitHub
  module Cache
    class Config
      autoload :Comparator, "github/cache/config/comparator"
      autoload :Servers, "github/cache/config/servers"

      ENV_CONFIG_PATH = "#{GitHub::AppEnvironment.root}/config/memcached_partitioned.yml"
      PROXY_CONFIG_PATH = "#{GitHub::AppEnvironment.root}/config/memcached_proxy.yml"
      SERVER_CONFIG_PATH = "#{GitHub::AppEnvironment.root}/config/memcached_servers.yml"

      class Environment < T::Enum
        enums do
          Default = new
          Dotcom = new
          Proxima = new
          Enterprise = new
        end
      end

      def initialize(overrides: nil)
        @overrides = overrides
      end

      sig { params(partition: Symbol, sites: T.nilable(T::Array[String]), bypass_proxy: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
      def for_partition(partition, sites: nil, bypass_proxy: false)
        server_list = servers(partition:, sites:, bypass_proxy:)
        config = partition_config(partition).merge({ servers: server_list })
        config = config.merge(single_server_overrides(server_list))
        config = config.merge(proxy_overrides(partition)) unless bypass_proxy

        return config.merge(@overrides) if @overrides

        config
      end

      def partitions
        env_config.symbolize_keys.keys
      end

      sig { returns(String) }
      def redis_namespace
        # Returns the base namespace for Redis keys. RedisClient#redis composes the
        # final Redis::Namespace as "#{namespace}:#{partition}", so the effective key
        # prefixes look like:
        #   "github-production:cache:global", "github-production:cache:usercontent"
        #   "proxima:test-cnc-01:cache:global", "enterprise-production:cache:global"
        case
        when GitHub.multi_tenant_enterprise?
          # Include stamp name to isolate Redis data between Proxima stamps
          # e.g., "proxima:test-cnc-01:cache:global"
          stamp = GitHub::Config::Proxima.current_stamp
          stamp ? "proxima:#{stamp}:cache" : "proxima:cache"
        when GitHub.review_lab?
          "review-lab:cache"
        when GitHub.single_tenant_enterprise?
          "enterprise-production:cache"
        when GitHub::AppEnvironment.production?
          # e.g., "github-production:cache:global", "github-production:cache:usercontent"
          "github-production:cache"
        else
          # e.g., "github-development:cache:global", "github-test:cache:usercontent"
          "github-#{GitHub::AppEnvironment.env}:cache"
        end
      end

      private

      # When only a single memcached server is configured on a standalone GHES
      # appliance, disable dead-host marking. libmemcached only marks a host dead
      # when server_failure_limit is non-zero AND retry_timeout is set; setting
      # server_failure_limit to 0 prevents Memcached::ServerIsMarkedDead from ever
      # being raised. With no failover peer, ejecting the sole host only produces a
      # ~retry_timeout window where every op raises and the get_multi fallback
      # amplifies logging. Slow ops instead surface as retryable timeouts that are
      # swallowed (cache miss). Gated ON by default so it needs no ghe-config key on
      # the appliance; set GITHUB_MEMCACHED_SINGLE_SERVER_NO_EJECT=0 to opt out.
      sig { params(server_list: T::Array[String]).returns(T::Hash[Symbol, T.untyped]) }
      def single_server_overrides(server_list)
        return {} unless environment == Environment::Enterprise
        return {} unless server_list.is_a?(Array) && server_list.size == 1
        return {} unless ENV.fetch("GITHUB_MEMCACHED_SINGLE_SERVER_NO_EJECT", "1") == "1"

        { server_failure_limit: 0, auto_eject_hosts: false }
      end

      # Returns proxy-optimized client settings for partitions routing through the
      # memcached proxy. Requires both MEMCACHED_PROXY_ENABLED and the per-partition
      # MEMCACHED_<PARTITION>_SERVERS env var to be set, ensuring proxy client tuning
      # is only applied when the partition is actually routed through the proxy.
      sig { params(partition: Symbol).returns(T::Hash[Symbol, T.untyped]) }
      def proxy_overrides(partition)
        return {} unless GitHub.kube?
        return {} unless ENV["MEMCACHED_PROXY_ENABLED"] == "true"
        return {} unless ENV["MEMCACHED_#{partition.to_s.upcase}_SERVERS"].presence

        proxy_config
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def proxy_config
        YAML.load(File.read(PROXY_CONFIG_PATH)).symbolize_keys
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def env_config
        data = ERB.new(File.read(ENV_CONFIG_PATH)).result
        config = YAML.load(data, aliases: true)
        env = if environment == Environment::Proxima
          "proxima"
        else
          GitHub::AppEnvironment.env
        end

        config[env]
      end

      sig { params(partition: Symbol).returns(T::Hash[Symbol, T.untyped]) }
      def partition_config(partition)
        raise ArgumentError.new("No config found for partition: #{partition}") unless partitions.include?(partition)

        config = env_config[partition.to_s].symbolize_keys

        config[:codec] = GitHub::Cache::Codec
        config[:namespace] ||= "github-"
        config[:namespace] << if GitHub.employee_unicorn?
          GitHub.host_name[0..9]
        else
          GitHub::AppEnvironment.env
        end
        config
      end

      sig { params(partition: Symbol, sites: T.nilable(T::Array[String]), bypass_proxy: T::Boolean).returns(T::Array[String]) }
      def servers(partition:, sites: nil, bypass_proxy: false)
        env = environment
        case env
        when Environment::Dotcom
          Servers::Dotcom.new.servers(partition:, sites:, bypass_proxy:)
        when Environment::Proxima
          Servers::Proxima.new.servers
        when Environment::Enterprise
          Servers::Enterprise.new.servers
        when Environment::Default
          Servers::Default.new.servers
        else
          T.absurd(env)
        end
      end

      sig { returns(Environment) }
      def environment
        case
        when GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test?
          Environment::Default
        when GitHub.multi_tenant_enterprise?
          Environment::Proxima
        when GitHub.single_tenant_enterprise?
          Environment::Enterprise
        when GitHub::AppEnvironment.production?
          Environment::Dotcom
        else
          Environment::Default
        end
      end
    end
  end
end
