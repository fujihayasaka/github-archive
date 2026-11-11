# typed: strict
# frozen_string_literal: true

module GitHub
  module RemoteCache
    # Factory module for creating remote cache clients.
    #
    # This module provides a standard pattern for creating cache modules that provide
    # `GitHub::RemoteCache::Client` instances. It's typically used in conjunction with
    # `GitHub::RemoteCache::Preset` to provide a clean, domain-specific caching interface.
    #
    # The factory caches client instances per domain to avoid creating redundant clients.
    #
    # Example usage:
    #
    #   module Issues
    #     module Cache
    #       extend GitHub::RemoteCache::ClientFactory
    #
    #       REMOTE_CACHE_NAMESPACE = "issues"
    #
    #       sig { override.returns(GH::Domain::Base) }
    #       private_class_method def self.domain_instance
    #         Issues.domain
    #       end
    #
    #       sig { override.returns(String) }
    #       private_class_method def self.namespace
    #         REMOTE_CACHE_NAMESPACE
    #       end
    #     end
    #   end
    #
    #   # Now you can access the cache client from anywhere:
    #   Issues::Cache.client  # => GitHub::RemoteCache::Client instance
    #
    # See `GitHub::RemoteCache::Preset` for how to use this in preset classes.
    module ClientFactory
      extend T::Helpers
      abstract!

      sig { returns(GitHub::RemoteCache::Client) }
      def client
        # Check cache first to avoid redundant RemoteCache.create() calls which
        # include feature flag preloading and object allocations on every invocation.
        if GitHub.remote_cache_mode && (registry = GH.context.remote_cache_registry)
          key = cache_client_key
          registry[key] ||= GitHub::RemoteCache.create(namespace: namespace, override: remote_cache_override)
        else
          GitHub::RemoteCache.create(namespace: namespace, override: remote_cache_override)
        end
      end

      private

      sig { returns(String) }
      def cache_client_key
        "#{namespace}:#{domain_instance.object_id}"
      end

      sig { abstract.returns(GH::Domain::Base) }
      def domain_instance; end

      sig { abstract.returns(String) }
      def namespace; end

      sig { returns(GitHub::RemoteCacheOverride) }
      def remote_cache_override
        GH.context.remote_cache_override
      end
    end
  end
end
