# typed: true
# frozen_string_literal: true

require "github"

module GitHub
  module Config
    # Mixin for the GitHub module that gives access to the memcache config
    # and also a memoized GitHub::Cache::Client singleton for memcache access.
    module Memcache
      include Kernel

      def partition_config
        require "erb"
        require "yaml"

        file = "#{GitHub::AppEnvironment.root}/config/memcached.yml"
        config = YAML.load(ERB.new(File.read(file)).result)
        config[GitHub::AppEnvironment.env]&.delete("partitions")&.symbolize_keys || {}
      end

      def cache_config
        require "erb"
        require "yaml"

        file = "#{GitHub::AppEnvironment.root}/config/memcached.yml"
        options = YAML.load(ERB.new(File.read(file)).result)

        # remove key before passing config to wrapped memcached client
        if options[GitHub::AppEnvironment.env]&.has_key? "partitions"
          options[GitHub::AppEnvironment.env]&.delete("partitions")
        end

        config = {}
        options["defaults"].each { |k, v| config[k.to_sym] = v }
        options[GitHub::AppEnvironment.env]&.each  { |k, v| config[k.to_sym] = v }
        config[:codec] = GitHub::Cache::Codec
        config[:namespace] ||= "github-"
        config[:namespace] << if GitHub.employee_unicorn?
          GitHub.host_name[0..9]
        else
          GitHub::AppEnvironment.env
        end
        config
      end

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

      module Dalli
        class KeyManager
          NAMESPACE_SEPARATOR = "" # or nil
        end
      end

      def dalli
        return @dalli if defined?(@dalli)
        target_partition = :htmlpipeline.freeze
        config = cache_config
        partition = partition_config[target_partition]
        if partition
          options = {
            namespace: config[:namespace],
            expires_in: config[:default_ttl],
            failover: config[:auto_eject_hosts],
            socket_max_failures: config[:server_failure_limit],
            socket_failure_delay: config[:connect_timeout],
            down_retry_delay: config[:retry_timeout],
          }
          @dalli = GitHub::Cache::DalliClient.new(partition["servers"], options)
        end
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
        @regional_caches ||= begin
          caches = {}
          datacenter_servers.each do |dc, servers|
            config = cache_config.merge(no_block: true, noreply: true, servers: servers)
            client = GitHub::Cache::Client.new(config)
            caches[dc] = client
          end
          caches
        end
      end

      private

      # Private: Create and return the default cache client
      def default_cache_client
        config = cache_config
        cache = GitHub::Cache::Client.new(config)
        cache.servers = Array(config.delete(:servers))
        cache_partitions[:global] = cache

        # create a new cache client for each partition if not already present
        # and change it's server list at runtime. More details at:
        # vendor/gems/2.7.1/ruby/2.7.0/gems/memcached-1.8.0/lib/memcached/memcached.rb:257
        partition_config.each do |key, partition|
          client = GitHub::Cache::Client.new(config)
          client.current_partition = key
          client.set_runtime_servers partition["servers"]
          cache_partitions[key] = client
        end

        cache_partitions[:global]
      end

      def datacenter_servers
        datacenters = {}
        # Each region has a variable like `IAD_MEMCACHED_CLUSTERS` containing values
        # like `CP1_IAD_MEMCACHED_SERVERS,VA3_IAD_MEMCACHED_SERVERS,AC4_IAD_MEMCACHED_SERVERS`
        regional_clusters = GitHub.environment["MEMCACHED_CLUSTERS"]

        unless regional_clusters.blank?
          regional_clusters.split(/,\s*/).each do |regional_cluster|
            memcache_nodes = GitHub.environment[regional_cluster]
            dc = env_site_name(regional_cluster.chomp("_MEMCACHED_SERVERS"))
            if dc != GitHub.server_site && !memcache_nodes.blank?
              datacenters[dc] = memcache_nodes.split(/,\s*/)
            end
          end
        end
        datacenters
      end

      def env_site_name(dc)
        dc.downcase.gsub("_", "-")
      end
    end
  end

  extend Config::Memcache
end
