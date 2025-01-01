# typed: strict
# frozen_string_literal: true

module GitHub
  module Cache
    class ClientBuilder
      PRODUCTION_SITES = %w( ac4-iad va3-iad ash1-iad ).freeze

      sig { params(partition: Symbol, sites: T.nilable(T::Array[String])).returns(GitHub::Cache::Client) }
      def self.client_for(partition:, sites: nil)
        client_for_config(partition:, sites:, config: GitHub::Cache::Config.new)
      end

      sig { params(partition: Symbol, sites: T.nilable(T::Array[String])).returns(GitHub::Cache::Client) }
      def self.non_blocking_client_for(partition:, sites: nil)
        config = GitHub::Cache::Config.new(overrides: { no_block: true, noreply: true })
        client_for_config(partition:, sites:, config:)
      end

      sig { returns(T::Hash[Symbol, GitHub::Cache::Client]) }
      def self.clients_by_partition
        partitions = GitHub::Cache::Config.new.partitions
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
      private_class_method def self.client_for_config(partition:, sites: nil, config: GitHub::Cache::Config.new)
        partition_config = config.for_partition(partition, sites:)
        cache = GitHub::Cache::Client.new(partition_config)
        cache.current_partition = partition
        cache
      end

      sig { returns(T::Array[String]) }
      private_class_method def self.all_sites
        return [] if GitHub.single_or_multi_tenant_enterprise?

        return PRODUCTION_SITES if GitHub::AppEnvironment.production?

        []
      end
    end
  end
end
