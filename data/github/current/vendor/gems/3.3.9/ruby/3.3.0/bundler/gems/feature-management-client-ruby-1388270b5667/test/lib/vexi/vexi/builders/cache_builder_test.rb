# frozen_string_literal: true
# typed: true

require "test_helper"

require "vexi/builders/cache_builder"
require "vexi/configuration"

class CacheBuilderTest < Minitest::Test
  class TestCache
    include Vexi::Cache
    def cache_name; "test_cache" end
    def mget(keys); end
    def get(key); end
    def mset(key_value_pairs, lifetime = nil); end
    def set(key, value, lifetime = nil); end
  end

  def setup
    @config = Vexi::Configuration.new
    @cache_builder = Vexi::Builders::CacheBuilder.new(@config)
  end

  def test_in_memory
    @cache_builder.in_memory

    assert_equal(@config.cache_config.cache.cache_name, "in_memory")
  end

  def test_custom
    custom_cache = TestCache.new

    @cache_builder.custom(custom_cache, 300, 30)

    assert_equal(custom_cache, @config.cache_config.cache)
    assert_equal(@config.cache_config.cache.cache_name, "test_cache")
    assert_equal(300, @config.cache_config.ttl)
    assert_equal(30, @config.cache_config.not_found_ttl)
  end
end
