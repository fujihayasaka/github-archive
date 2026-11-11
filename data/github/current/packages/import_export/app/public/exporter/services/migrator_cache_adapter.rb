# typed: strict
# frozen_string_literal: true

module Exporter::Services
  # Adapter that wraps GitHub.cache to provide the same interface as GitHub::Migrator::Cache
  #
  # This allows exporter code to use the distributed GitHub.cache (backed by memcached/redis)
  # instead of the in-memory GitHub::Migrator::Cache, enabling cache sharing across processes
  # and persistence across restarts.
  #
  # The migration_guid is used to scope cache keys to a specific migration, preventing
  # cache collisions between different migration exports.
  #
  # Example:
  #   cache = Exporter::Services::MigratorCacheAdapter.new(migration_guid: "abc-123")
  #   cache.getset("key") { expensive_computation }
  class MigratorCacheAdapter
    DEFAULT_TTL = T.let(GitHub.max_gh_migrator_export_time, Integer)

    sig { returns(String) }
    attr_reader :migration_guid

    sig { params(migration_guid: String, ttl: Integer).void }
    def initialize(migration_guid:, ttl: DEFAULT_TTL)
      @migration_guid = migration_guid
      @ttl = ttl
    end

    # Public: Get a value from cache or compute and cache it.
    #
    # This method adapts GitHub.cache's fetch method to match the Migrator::Cache#getset interface.
    # Note: Like Migrator::Cache, this only caches truthy values (not nil or false).
    #
    # key - The String cache key (will be scoped with migration_guid)
    # block - Block to execute if cache miss occurs
    #
    # Returns the cached value or result of the block
    sig { params(key: String, block: T.proc.returns(T.untyped)).returns(T.untyped) }
    def getset(key, &block)
      scoped_key = cache_key(key)

      # Check if value exists in cache
      cached = GitHub.cache.get(scoped_key)
      return cached if cached

      # Compute new value
      value = yield
      # Only cache truthy values, matching Migrator::Cache behavior
      GitHub.cache.set(scoped_key, value, @ttl) if value
      value
    end

    # Public: Clear the cache.
    #
    # Note: This is a no-op for the distributed cache adapter since we can't
    # easily clear just the keys we've set. In the distributed cache context,
    # individual keys expire based on TTL.
    sig { void }
    def clear
      # No-op: distributed cache uses TTL-based expiration
    end

    private

    # Private: Generate a scoped cache key using the migration_guid
    sig { params(key: String).returns(String) }
    def cache_key(key)
      "migration:#{@migration_guid}:#{key}"
    end
  end
end
