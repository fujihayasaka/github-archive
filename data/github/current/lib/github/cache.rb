# typed: true
# frozen_string_literal: true

require "memcached"

module GitHub
  # The GitHub memcache client stack. This is basically Rails's standard
  # memcache interface with a variety of extra features strapped on top.
  #
  # The GitHub::Cache::Client class is the main client interface available via
  # the top-level GitHub.cache instance. It mixes in a variety of features from the
  # other modules defined here.
  module Cache
    autoload :BigInteger,      "github/cache/big_integer"
    autoload :Client,          "github/cache/client"
    autoload :ClientBuilder,   "github/cache/client_builder"
    autoload :Codec,           "github/cache/codec"
    autoload :Config,          "github/cache/config"
    autoload :DisableWrite,    "github/cache/disable_write"
    autoload :EncodedString,   "github/cache/encoded_string"
    autoload :Failover,        "github/cache/failover"
    autoload :Fake,            "github/cache/fake"
    autoload :FakeAsync,       "github/cache/fake_async"
    autoload :FakeConfig,      "github/cache/fake_config"
    autoload :FakeResponse,    "github/cache/fake_response"
    autoload :HashKeys,        "github/cache/hash_keys"
    autoload :Instrumentation, "github/cache/instrumentation"
    autoload :Local,           "github/cache/local"
    autoload :LongTTL,         "github/cache/long_ttl"
    autoload :Partition,       "github/cache/partition"
    autoload :ResetMiddleware, "github/cache/reset_middleware"
    autoload :SafeBuffer,      "github/cache/safe_buffer"
    autoload :Skip,            "github/cache/skip"
    autoload :Timid,           "github/cache/timid"
    autoload :Utils,           "github/cache/utils"
    autoload :WithoutMixins,   "github/cache/without_mixins"
    autoload :Zip,             "github/cache/zip"
  end
end

# Massage the Memcached::Rails interface to be a bit more compliant with Rails's
# built-in MemCache interface.
class Memcached::Rails
  def servers=(servers)
    set_servers(servers)
  end

  # Revert to pre-v1.7.0 raise errors behavior for compatibility with Cache::Client
  def log_exception(e)
    raise e
  end
end
