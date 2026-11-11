# typed: true
# frozen_string_literal: true

require "github"

module GitHub
  module Config
    # Mixin for the GitHub module that gives access to the memcache config
    # and also a memoized GitHub::Cache::Client singleton for memcache access.
    module Memcache
      include Kernel

      # Public: Return the GitHub::Cache instance
      def cache
        return @cache if defined?(@cache)

        # Take care when updating `self.cache` here as this eventually sets
        # the global Rails cache to be used across the application.
        self.cache = default_cache_client
      end

      # Public: Set the GitHub cache store and set up Rails cache store (if
      # we are in a GitHub::AppEnvironment.environment)
      def cache=(cache)
        @cache = cache
        set_up_rails_cache_store
        @cache
      end

      # Public: Return the current GitHub::LazyMemcache instance for the
      # request if any. If not set return a client with an API that is
      # compatible with GitHub::LazyMemcache but backed by GitHub.cache
      # (i.e. it flushes immediately)
      def lazy_cache
        if @lazy_cache
          @lazy_cache
        else
          # Out of typical Unicorn request cycle; use the lazy cache API in passthrough mode.
          ::GitHub.dogstats.increment("lazy_memcache.passthrough_activated")
          @lazy_cache = LazyMemcache::PassThrough.new(cache)
        end
      end

      # Public: Set the GitHub cache store and set up Rails cache store (if
      # we are in a GitHub::AppEnvironment.environment)
      def lazy_cache=(cache)
        @lazy_cache = cache
      end

      # Public: Return a hash of GitHub::Cache instance partitions
      def cache_partitions
        @cache_partitions ||= Hash.new
      end

      # Public: Set the global Rails cache stores.  We do this carefully with
      # defined? calls because there are areas where we set up the cache
      # where we do not have the GitHub::AppEnvironment.environment loaded.
      def set_up_rails_cache_store
        ::GitHub::Application.config.cache_store = GitHub.cache if defined?(::GitHub::Application)
        ::ActionController::Base.cache_store = GitHub.cache if defined?(::ActionController::Base)
      end

      def regional_caches
        return @regional_caches if defined?(@regional_caches)

        @regional_caches = GitHub::Cache::ClientBuilder.regional_clients_by_site
      end

      private

      # Private: Create and return the default cache client
      def default_cache_client
        partition_clients = GitHub::Cache::ClientBuilder.clients_by_partition
        partition_clients.each_pair do |key, client|
          cache_partitions[key] = client
        end

        cache_partitions[:global]
      end
    end
  end

  extend Config::Memcache
end
