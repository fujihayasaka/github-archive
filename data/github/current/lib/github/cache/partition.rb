# typed: true
# frozen_string_literal: true

module GitHub
  module Cache

    # Mixin for allowing callers of `GitHub.cache` to use a specific partition

    # Partitions use a separate `GitHub::Cache` instance from the global
    # Rails cache and are accessible via `GitHub.cache.for_partition(:partition)`.
    #
    # Examples:
    #
    # ```rb
    # GitHub.cache.for_partition(:packages).delete("repository:packages:count:#{repo.id}")
    # ```
    #
    # ```rb
    # cached = GitHub.cache.for_partition(:gitrpc).get_multi(fileserver_disk_stats.map(&:cache_key)
    #        + fileserver_disk_stats.map(&:error_cache_key))
    # ```
    #
    # Only the dotcom environment is supported.  When a caller attempts to use a
    # partition from an enterprise deployment, we route requests to the global
    # Rails cache.
    module Partition
      extend T::Helpers
      requires_ancestor { GitHub::Cache::ICache }
      requires_ancestor { GitHub::Cache::ICacheConfig }
      include Kernel

      attr_accessor :current_partition

      # Return the GitHub::Cache instance for a partition key.
      # Enterprise environments are not supported and are forced to return the
      # global GitHub::Cache instance.
      def for_partition(key)
        return GitHub.cache_partitions[:global] if GitHub.single_or_multi_tenant_enterprise?
        if !GitHub.cache_partitions.key? key
          raise ArgumentError, "`#{key}` does not match partitions in `memcached.yml`"
        end
        GitHub.cache_partitions[key]
      end

      # Disable use of a partition by swapping for the global Rails cache client
      # (experimental)
      # Example:
      # ```rb
      # # Disable cache partition for all callers to `GitHub.cache.for_partition(:p)`
      # # if self.respond_to? :current_partition
      # #   p = self.current_partition
      # #   GitHub.cache.disable_partition p
      # # end
      # ```
      def disable_partition(key)
        if !GitHub.cache_partitions.key? key
          logger.warn "disable partition `#{key}` not found in `memcached.yml`" if logger
          return GitHub.cache_partitions[:global]
        end
        GitHub.cache_partitions[key] = GitHub.cache_partitions[:global]
      end

      # Change a client's server list at runtime. Expects to be called to
      # reconfigure a default GitHub::Cache::Client according to partitions
      # defined in `memcached.yml`.
      # More details at the following links:
      # - vendor/gems/2.7.1/ruby/2.7.0/gems/memcached-1.8.0/lib/memcached/memcached.rb:257
      # - https://cloudbur.st/evan/memcached/classes/Memcached.html#M000010
      # - https://rubygems.org/gems/memcached/versions/1.8.0
      def set_runtime_servers(servers)
        self.set_servers servers
        self.reset servers
      end
    end
  end
end
