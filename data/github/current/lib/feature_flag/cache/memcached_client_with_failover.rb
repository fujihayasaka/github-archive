# typed: strict
# frozen_string_literal: true

module FeatureFlag
  module Cache
    # A feature flag memcached client that supports failover.
    # Used by unicorn workers for read operations (get/get_multi).
    # Note: Make sure to include any non-failover changes made to this class in the non-failover version as well.
    class MemcachedClientWithFailover < MemcachedClient
      # NOTE: The order these mixins are included is important.

      if GitHub.foreground? || GitHub::AppEnvironment.test? || GitHub::AppEnvironment.development?
        prepend FeatureFlag::Cache::Instrumentation
      end

      # Mixin for Memcached::Rails that adds error swallowing and reliable server failover.
      include GitHub::Cache::Failover

      # Opt into disconnecting on ProtocolError before retry.
      # ProtocolError means the TCP buffer has stale/garbled data from a partial read.
      # Calling quit closes sockets so the retry auto-reconnects on a clean connection
      # instead of reading more garbage from the same corrupted stream.
      #
      # Gated by FEATUREFLAG_QUIT_ON_PROTOCOL_ERROR env var for gradual rollout.
      # quit() disconnects from all servers (not just the corrupted one), so we want
      # to confirm reconnect fanout is acceptable before enabling globally.
      sig { override.returns(T::Boolean) }
      def quit_on_protocol_error?
        ENV["FEATUREFLAG_QUIT_ON_PROTOCOL_ERROR"] == "1"
      end

      # Disable CAS for the read path. The read path (get/get_multi) never performs CAS operations.
      # Disabling removes 8 extra bytes per key from GET responses, reducing response payload size
      # and lowering the risk of Memcached::ProtocolError from partial reads on tight timeouts.
      sig { override.returns(T::Boolean) }
      def self.support_cas?
        false
      end

      # Mixin for transparently compressing and decompressing values
      include FeatureFlag::Cache::LZ4

      # Mixin for truncating and hashing long keys.
      # This is a hard limit in the memcached client and will raise if the key exceeds 250 characters,
      # which includes the prefix_key / namespace.
      include GitHub::Cache::HashKeys

      # Mixin for disallowing long TTLs (longer than 30 day). We shouldn't need this for feature flags, but probably doesn't hurt to include it.
      include GitHub::Cache::LongTTL

      # Extended timeout for get_multi operations.
      # Single-key gets use the default 20ms timeout, but get_multi with many keys
      # produces larger responses that may not arrive within 20ms, causing partial reads
      # that corrupt the TCP buffer and cascade into Memcached::ProtocolError on subsequent ops.
      GET_MULTI_TIMEOUT = 0.25 # 250ms
      DEFAULT_TIMEOUT = 0.02 # 20ms

      # Use WithoutRuntime.sig because Instrumentation::Tracing is prepended and defines
      # get_multi; sorbet-runtime does not support replacing methods in prepended modules.
      T::Sig::WithoutRuntime.sig { override.params(keys: T::Array[String], raw: T::Boolean).returns(T::Hash[String, T.untyped]) }
      def get_multi(keys, raw = false)
        if keys.length > 1
          send(:set_behavior, :rcv_timeout, GET_MULTI_TIMEOUT)
          send(:set_behavior, :poll_timeout, GET_MULTI_TIMEOUT)
        end
        super
      ensure
        if keys.length > 1
          send(:set_behavior, :rcv_timeout, DEFAULT_TIMEOUT)
          send(:set_behavior, :poll_timeout, DEFAULT_TIMEOUT)
        end
      end
    end
  end
end
