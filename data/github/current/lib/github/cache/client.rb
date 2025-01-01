# typed: true
# frozen_string_literal: true

module GitHub
  module Cache
    # Rails memcached interface with custom extensions.
    class Client < Memcached::Rails

      # NOTE: This MUST be included first, before the prepend below, otherwise
      # it won't be able to alias the true origin methods.
      include GitHub::Cache::WithoutMixins
      include ICache
      include ICacheConfig
      include IAsyncCache

      if GitHub.foreground? || GitHub::AppEnvironment.test? || GitHub::AppEnvironment.development?
        prepend GitHub::Cache::Instrumentation
      end

      attr_accessor :logger

      # NOTE: The order these mixins are included is important. Especially the
      # Zip, Failover and Partition modules.
      include GitHub::Cache::FakeAsync # until IOPromise replaces it
      include GitHub::Cache::Failover
      include GitHub::Cache::Partition
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
