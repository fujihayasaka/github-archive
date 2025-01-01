# typed: true
# frozen_string_literal: true

require "test_helper"
require "github/cache"

class GitHubCacheUtilsMixinTest < GitHub::TestCase
  class TestCacheClass < Memcached::Rails
    include GitHub::Cache::Timid
    include GitHub::Cache::FakeAsync
    include GitHub::Cache::Utils
    include GitHub::Cache::ICacheConfig
  end

  setup do
    @cache = TestCacheClass.new
    @cache.allow = /.*/
  end

  context "#fetch" do
    test "returns the cached value, if the cache key exists" do
      @cache.store["some-key"] = GitHub::Cache::Codec.pack("some value")

      assert_equal "some value", @cache.fetch("some-key") { fail "should not be executed" }
    end

    test "returns the result of the given block when the cache key does not exist" do
      assert_equal "calculated", @cache.fetch("some-key") { "calculated" }
    end

    test "stores the result of the given block when the cache key does not exist" do
      @cache.fetch("some-key") { "calculated" }

      assert_equal true, @cache.store.has_key?("some-key")
      assert_equal "calculated", GitHub::Cache::Codec.unpack(@cache.store["some-key"])
    end

    test "stores `nil` values" do
      @cache.fetch("some-key") { nil }

      assert_equal true, @cache.store.has_key?("some-key")
      assert_nil GitHub::Cache::Codec.unpack(@cache.store["some-key"])
    end

    test "correctly handles `nil` values written via `#set`" do
      @cache.set("some-key", nil)

      assert_nil @cache.fetch("some-key") { fail "should not be executed" }
    end

    test "correctly handles legacy `nil` values" do
      @cache.store["some-key"] = GitHub::Cache::Codec.pack(:_nil)

      assert_nil @cache.fetch("some-key") { fail "should not be executed" }
    end
  end

  context "#async_get_or_cache" do
    test "returns the cached value, if the cache key exists" do
      @cache.store["some-key"] = GitHub::Cache::Codec.pack("some value")

      p = @cache.async_get_or_cache("some-key") { fail "should not be executed" }
      assert_equal "some value", p.sync
    end

    test "returns the result of the given block when the cache key does not exist" do
      p = @cache.async_get_or_cache("some-key") { "calculated" }
      assert_equal "calculated", p.sync
    end

    test "stores the result of the given block when the cache key does not exist" do
      p = @cache.async_get_or_cache("some-key") { "calculated" }
      p.sync

      assert_equal true, @cache.store.has_key?("some-key")
      assert_equal "calculated", GitHub::Cache::Codec.unpack(@cache.store["some-key"])
    end

    test "stores `nil` values" do
      p = @cache.async_get_or_cache("some-key") { nil }
      p.sync

      assert_equal true, @cache.store.has_key?("some-key")
      assert_nil GitHub::Cache::Codec.unpack(@cache.store["some-key"])
    end

    test "correctly handles `nil` values written via `#set`" do
      @cache.set("some-key", nil)

      p = @cache.async_get_or_cache("some-key") { fail "should not be executed" }
      assert_nil p.sync
    end

    test "correctly handles `nil` values written via `#async_set`" do
      @cache.async_set("some-key", nil).sync

      p = @cache.async_get_or_cache("some-key") { fail "should not be executed" }
      assert_nil p.sync
    end

    test "correctly handles legacy `nil` values" do
      @cache.store["some-key"] = GitHub::Cache::Codec.pack(:_nil)

      p = @cache.async_get_or_cache("some-key") { fail "should not be executed" }
      assert_nil p.sync
    end
  end

  context "#get" do
    test "correctly handles reading `nil` values stored via #fetch" do
      @cache.fetch("some-key") { nil }
      assert_nil @cache.get("some-key")
    end

    test "correctly handles legacy `nil` values" do
      @cache.store["some-key"] = GitHub::Cache::Codec.pack(:_nil)
      assert_nil @cache.get("some-key")
    end
  end

  context "#async_get" do
    test "correctly handles reading `nil` values stored via #fetch" do
      @cache.fetch("some-key") { nil }
      res = @cache.async_get("some-key").sync
      assert_nil res.value
      assert_equal true, res.exist?
    end

    test "correctly handles reading `nil` values stored via #async_get_or_cache" do
      p = @cache.async_get_or_cache("some-key") { nil }
      p.sync
      res = @cache.async_get("some-key").sync
      assert_nil res.value
      assert_equal true, res.exist?
    end

    test "correctly handles legacy `nil` values" do
      @cache.store["some-key"] = GitHub::Cache::Codec.pack(:_nil)
      res = @cache.async_get("some-key").sync
      assert_nil res.value
      assert_equal true, res.exist?
    end
  end

  context "#get_multi" do
    test "correctly handles reading `nil` values stored via #fetch" do
      @cache.fetch("some-key") { nil }
      assert_equal({ "some-key" => nil }, @cache.get_multi(["some-key"]))
    end

    test "correctly handles legacy `nil` values" do
      @cache.store["some-key"] = GitHub::Cache::Codec.pack(:_nil)
      assert_equal({ "some-key" => nil }, @cache.get_multi(["some-key"]))
    end
  end

  context "#async_get_multi" do
    test "correctly handles reading `nil` values stored via #fetch" do
      @cache.fetch("some-key") { nil }
      assert_equal({ "some-key" => nil }, @cache.async_get_multi(["some-key"]).sync)
    end

    test "correctly handles reading `nil` values stored via #async_get_or_cache" do
      p = @cache.async_get_or_cache("some-key") { nil }
      p.sync
      assert_equal({ "some-key" => nil }, @cache.async_get_multi(["some-key"]).sync)
    end

    test "correctly handles legacy `nil` values" do
      @cache.store["some-key"] = GitHub::Cache::Codec.pack(:_nil)
      assert_equal({ "some-key" => nil }, @cache.async_get_multi(["some-key"]).sync)
    end
  end

  context "#exist?" do
    test "handles non-existing keys" do
      assert_equal false, @cache.exist?("some-key")
    end

    test "handles keys with a value" do
      @cache.store["some-key"] = GitHub::Cache::Codec.pack("some-value")
      assert_equal true, @cache.exist?("some-key")
    end

    test "handles keys with a `nil` value" do
      @cache.store["some-key"] = GitHub::Cache::Codec.pack(nil)
      assert_equal true, @cache.exist?("some-key")
    end

    test "correctly handles `nil` values stored via #fetch" do
      @cache.fetch("some-key") { nil }
      assert_equal true, @cache.exist?("some-key")
    end
  end

  context "#async_exist?" do
    test "handles non-existing keys" do
      assert_equal false, @cache.async_exist?("some-key").sync
    end

    test "handles keys with a value" do
      @cache.store["some-key"] = GitHub::Cache::Codec.pack("some-value")
      assert_equal true, @cache.async_exist?("some-key").sync
    end

    test "handles keys with a `nil` value" do
      @cache.store["some-key"] = GitHub::Cache::Codec.pack(nil)
      assert_equal true, @cache.async_exist?("some-key").sync
    end

    test "correctly handles `nil` values stored via #fetch" do
      @cache.fetch("some-key") { nil }
      assert_equal true, @cache.async_exist?("some-key").sync
    end
  end
end
