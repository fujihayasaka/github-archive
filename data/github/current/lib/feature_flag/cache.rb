# typed: strict
# frozen_string_literal: true

module FeatureFlag
  module Cache
    autoload :Codec, "feature_flag/cache/codec"
    autoload :Fake, "feature_flag/cache/fake"
    autoload :IMemcachedClient, "feature_flag/cache/i_memcached_client"
    autoload :Instrumentation, "feature_flag/cache/instrumentation"
    autoload :LZ4, "feature_flag/cache/lz4"
    autoload :MemcachedClient, "feature_flag/cache/memcached_client"
    autoload :MemcachedClientWithFailover, "feature_flag/cache/memcached_client_with_failover"
    autoload :MemcachedClientWithoutFailover, "feature_flag/cache/memcached_client_without_failover"
    autoload :MsgPack, "feature_flag/cache/msgpack"
    autoload :Timid, "feature_flag/cache/timid"
  end
end
