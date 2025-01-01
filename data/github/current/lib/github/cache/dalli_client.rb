# typed: true
# frozen_string_literal: true
require "dalli"

module GitHub
  module Cache
    # The DalliClient is meant to be a close copy of the GitHub::Cache::Client -
    # it uses the same mixins (except for instrumentation) and implements the same interface.
    class DalliClient < Dalli::Client
      # the methods below were added to keep the interface compatible with the default client
      # and to satisfy the ICacheConfig interface which is required by some of our middleware.

      def initialize(server_structs, options = {})
        @namespace = options[:namespace] || "github"
        super(server_structs, options)
      end

      def prefix_key
        @namespace
      end

      def exist?(key)
        get(key) != nil
      rescue Dalli::DalliError => e
        false
      end

      def set_servers(server_structs); end
      def server_by_key(key); end
      def options; end
      def reset(server_structs); end


      # NOTE: This MUST be included first, before the prepend below, otherwise
      # it won't be able to alias the true origin methods.
      include GitHub::Cache::WithoutMixins
      include ICache
      include ICacheConfig
      include IAsyncCache

      attr_accessor :logger

      # NOTE: The order these mixins are included is important. Especially the
      # Zip, Failover and Partition modules.
      include GitHub::Cache::Compatibility
      include GitHub::Cache::FakeAsync # until IOPromise replaces it
      include GitHub::Cache::DalliFailover
      include GitHub::Cache::Zip
      include GitHub::Cache::Local
      include GitHub::Cache::Utils
      include GitHub::Cache::Skip
      include GitHub::Cache::DisableWrite
      include GitHub::Cache::HashKeys
      include GitHub::Cache::LongTTL

    end
  end
end
