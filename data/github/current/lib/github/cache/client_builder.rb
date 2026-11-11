# typed: strict
# frozen_string_literal: true

module GitHub
  module Cache
    class ClientBuilder
      PRODUCTION_SITES = %w( ac4-iad va3-iad ash1-iad ).freeze

      sig { params(partition: Symbol, sites: T.nilable(T::Array[String])).returns(T.any(GitHub::Cache::Client, GitHub::Cache::DualClient)) }
      def self.client_for(partition:, sites: nil)
        config = GitHub::Cache::Config.new

        # For Proxima test-cnc-01 stamp, use DualClient to allow per-request routing decision
        if use_dual_cache_client
          return dual_client_for(partition: partition, sites: sites, config: config)
        end

        client_for_config(partition:, sites:, config: config)
      end

      sig { params(partition: Symbol, sites: T.nilable(T::Array[String])).returns(GitHub::Cache::Client) }
      def self.non_blocking_client_for(partition:, sites: nil)
        config = GitHub::Cache::Config.new(overrides: { no_block: true, noreply: true })
        client_for_config(partition:, sites:, config:)
      end

      sig { returns(T::Hash[Symbol, T.any(GitHub::Cache::Client, GitHub::Cache::DualClient)]) }
      def self.clients_by_partition
        config = GitHub::Cache::Config.new
        partitions = config.partitions
        partitions.each_with_object({}) do |partition, result|
          if partition == :global
            result[partition] = client_for(partition:, sites: [GitHub.server_site])
            next
          end

          result[partition] = client_for(partition:, sites: all_sites)
        end
      end

      sig { returns(T::Hash[String, GitHub::Cache::Client]) }
      def self.regional_clients_by_site
        all_sites.each_with_object({}) do |site, result|
          next if site == GitHub.server_site

          result[site] = non_blocking_client_for(partition: :global, sites: [site])
        end
      end

      sig { params(partition: Symbol, sites: T.nilable(T::Array[String]), config: GitHub::Cache::Config).returns(GitHub::Cache::Client) }
      def self.client_for_config(partition:, sites: nil, config: GitHub::Cache::Config.new)
        partition_config = config.for_partition(partition, sites:)
        cache = GitHub::Cache::Client.new(partition_config)
        cache.current_partition = partition
        cache
      end

      sig { returns(T::Array[String]) }
      def self.all_sites
        return [] if GitHub.review_lab?

        return [] if GitHub.single_or_multi_tenant_enterprise?

        if GitHub::AppEnvironment.production?

          # in IAD we connect all production site deployments to all memcached servers
          return PRODUCTION_SITES if PRODUCTION_SITES.include?(GitHub.server_site)

          # default to only connecting to the local site in production when not in IAD (when in Azure)
          return [GitHub.server_site]
        end

        []
      end

      sig { returns(T::Boolean) }
      def self.use_dual_cache_client
        if GitHub.multi_tenant_enterprise? || GitHub.review_lab?
          GitHub.environment.fetch("USE_DUAL_CACHE_CLIENT", false) == "true"
        else
          false
        end
      end

      sig { params(partition: Symbol, sites: T.nilable(T::Array[String]), config: GitHub::Cache::Config).returns(GitHub::Cache::DualClient) }
      def self.dual_client_for(partition:, sites: nil, config: GitHub::Cache::Config.new)
        # Build both Redis and Memcached clients
        redis_client = redis_client_for(partition: partition, config: config)
        memcached_client = client_for_config(partition: partition, sites: sites, config: config)

        # Wrap them in a DualClient that will route based on feature flag per request
        GitHub::Cache::DualClient.new(redis_client, memcached_client, partition)
      end

      sig { params(partition: Symbol, config: GitHub::Cache::Config).returns(GitHub::Cache::RedisClient) }
      def self.redis_client_for(partition:, config: GitHub::Cache::Config.new)
        namespace = config.redis_namespace
        redis_client = GitHub::Cache::RedisClient.new(namespace: namespace, partition: partition)
        redis_client.current_partition = partition
        redis_client
      end
    end
  end
end
