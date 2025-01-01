# typed: true
# frozen_string_literal: true

require "test_helper"
require "github/cache"

class FakeLocalCache < GitHub::Cache::Fake
  include GitHub::Cache::Local
end

class GitHubCacheLocalMixinTest < GitHub::TestCase
  setup do
    @cache = FakeLocalCache.new
    @cache.enable_local_cache
    @cache.allow = /.*/
  end

  test "does nothing when local cache is disabled" do
    @cache.local = nil
    assert_equal true, @cache.set("some-key", "some-value")
    assert_equal "some-value", @cache.get("some-key")
    assert_nil @cache.local
  end

  test "does nothing when local cache is disabled (async)" do
    @cache.local = nil
    assert_equal true, @cache.async_set("some-key", "some-value").sync.stored?
    assert_equal "some-value", @cache.async_get("some-key").sync.value
    assert_nil @cache.local
  end

  test "writes to local cache on get" do
    @cache.store["some-key"] = GitHub::Cache::Codec.pack("some-value")
    assert @cache.local.empty?
    assert_equal "some-value", @cache.get("some-key")
    assert_equal "some-value", @cache.local["some-key"]
  end

  test "writes to local cache on async_get" do
    @cache.store["some-key"] = GitHub::Cache::Codec.pack("some-value")
    assert @cache.local.empty?
    assert_equal "some-value", @cache.async_get("some-key").sync.value
    assert_equal "some-value", @cache.local["some-key"]
  end

  test "writes to local cache on set" do
    assert_equal true, @cache.set("some-key", "some-value")
    assert_equal "some-value", @cache.local["some-key"]
    assert_equal "some-value", @cache.get("some-key")
    assert_equal "some-value", @cache.local["some-key"]
  end

  test "writes to local cache on async_set" do
    assert_equal true, @cache.async_set("some-key", "some-value").sync.stored?
    assert_equal "some-value", @cache.local["some-key"]
    assert_equal "some-value", @cache.async_get("some-key").sync.value
    assert_equal "some-value", @cache.local["some-key"]
  end

  test "writes to local cache on add" do
    assert_nil @cache.get("some-key")
    assert_equal true, @cache.add("some-key", "some-value")
    assert_equal "some-value", @cache.get("some-key")
    assert_equal "some-value", @cache.local["some-key"]
  end

  test "writes to local cache on async_add" do
    assert_nil @cache.async_get("some-key").sync.value
    assert_equal true, @cache.async_add("some-key", "some-value").sync.stored?
    assert_equal "some-value", @cache.local["some-key"]
    assert_equal "some-value", @cache.async_get("some-key").sync.value
    assert_equal "some-value", @cache.local["some-key"]
  end

  test "does not write to local cache on add when key already exists" do
    assert_nil @cache.get("some-key")
    assert_equal true, @cache.add("some-key", "some-value")
    assert_nil @cache.add("some-key", "some-OTHER-value")
    assert_equal "some-value", @cache.local["some-key"]
  end

  test "does not write to local cache on async_add when key already exists" do
    assert_nil @cache.async_get("some-key").sync.value
    assert_equal true,  @cache.async_add("some-key", "some-value").sync.stored?
    assert_equal "some-value", @cache.local["some-key"]
    assert_equal false, @cache.async_add("some-key", "some-OTHER-value").sync.stored?
    assert_equal "some-value", @cache.local["some-key"]
  end

  test "writes to local cache on delete" do
    @cache.set("some-key", "some-value")
    assert_equal "some-value", @cache.local["some-key"]
    @cache.delete("some-key")
    assert !@cache.local.key?("some-key")
  end

  test "writes to local cache on async_delete" do
    @cache.async_set("some-key", "some-value").sync
    assert_equal "some-value", @cache.local["some-key"]
    @cache.async_delete("some-key").sync
    assert !@cache.local.key?("some-key")
    assert_equal false, @cache.async_get("some-key").sync.exist?
  end

  test "writes to local cache when setting nil value" do
    @cache.set("some-key", nil)
    assert_equal({ "some-key" => nil }, @cache.get_multi(["some-key"]))
  end

  test "writes to local cache when async_set with nil value" do
    @cache.async_set("some-key", nil).sync
    assert_equal({ "some-key" => nil }, @cache.get_multi(["some-key"]))
    assert_equal({ "some-key" => nil }, @cache.async_get_multi(["some-key"]).sync)
    assert_equal true, @cache.async_get("some-key").sync.exist?
    assert_nil @cache.async_get("some-key").sync.value
  end

  test "does not incorrectly cache multi get misses" do
    assert_equal({}, @cache.get_multi(["other-key"]))
    assert_equal({}, @cache.get_multi(["other-key"]))
  end

  test "does not incorrectly cache multi async_get misses" do
    assert_equal(false, @cache.async_get("other-key").sync.exist?)
    assert_equal(false, @cache.async_get("other-key").sync.exist?)
    assert_equal({}, @cache.async_get_multi(["other-key"]).sync)
    assert_equal({}, @cache.async_get_multi(["other-key"]).sync)
  end

  test "does not incorrectly cache get misses" do
    assert_nil @cache.get("other-key")
    assert_equal({}, @cache.get_multi(["other-key"]))
  end

  test "does not incorrectly cache async_get misses" do
    assert_equal(false, @cache.async_get("other-key").sync.exist?)
    assert_equal({}, @cache.async_get_multi(["other-key"]).sync)
    assert_equal(false, @cache.async_get("other-key").sync.exist?)
  end

  test "does handle nil values on get correctly" do
    @cache.store["other-key"] = GitHub::Cache::Codec.pack(nil)
    @cache.get("other-key")
    assert_equal({ "other-key" => nil }, @cache.get_multi(["other-key"]))

    res = @cache.async_get("other-key").sync
    assert_equal(true, res.exist?)
    assert_nil(res.value)
    assert_equal({ "other-key" => nil }, @cache.async_get_multi(["other-key"]).sync)
  end

  test "does handle missing values on get correctly" do
    @cache.get("other-key")
    assert_equal({}, @cache.get_multi(["other-key"]))

    res = @cache.async_get("other-key").sync
    assert_equal(false, res.exist?)
    assert_nil(res.value)
    assert_equal({}, @cache.async_get_multi(["other-key"]).sync)
  end

  test "keeps missing nil results in cache" do
    assert_nil @cache.get("some-key")
    @cache.store.expects(:[]).never
    assert_nil @cache.get("some-key")
  end

  test "keeps missing nil results in cache (async)" do
    assert_equal false, @cache.async_get("some-key").sync.exist?
    @cache.store.expects(:[]).never
    assert_equal false, @cache.async_get("some-key").sync.exist?
  end

  test "merges with local cache on get_multi" do
    @cache.local = { "1" => "a", "2" => "b" }
    @cache.store["3"] = GitHub::Cache::Codec.pack("c")
    @cache.store["1"] = GitHub::Cache::Codec.pack("X")
    res = @cache.get_multi(%w[1 2 3 4])
    assert_equal({ "1" => "a", "2" => "b", "3" => "c" }, res)
    assert_equal "c", @cache.local["3"]
    assert @cache.local.key?("4")
    assert_equal GitHub::Cache::Local::MISSING, @cache.local["4"]
  end

  test "merges with local cache on async_get_multi" do
    @cache.local = { "1" => "a", "2" => "b" }
    @cache.store["3"] = GitHub::Cache::Codec.pack("c")
    @cache.store["1"] = GitHub::Cache::Codec.pack("X")
    res = @cache.async_get_multi(%w[1 2 3 4]).sync
    assert_equal({ "1" => "a", "2" => "b", "3" => "c" }, res)
    assert_equal "c", @cache.local["3"]
    assert @cache.local.key?("4")
    assert_equal GitHub::Cache::Local::MISSING, @cache.local["4"]
  end

  test "is correct after an incr" do
    @cache.set("some-key", "1", 1.hour, true)
    assert_equal "1", @cache.get("some-key")
    assert_equal 2, @cache.incr("some-key")
    assert_equal 2, @cache.get("some-key")
  end

  test "is correct after an async_incr" do
    @cache.set("some-key", "1", 1.hour, true)
    assert_equal "1", @cache.get("some-key")
    assert_equal 2, @cache.async_incr("some-key").sync.value
    assert_equal 2, @cache.get("some-key")
  end

  test "is correct after an decr" do
    @cache.set("some-key", "10", 1.hour, true)
    assert_equal "10", @cache.get("some-key")
    assert_equal 9, @cache.decr("some-key")
    assert_equal 9, @cache.get("some-key")
  end

  test "is correct after an async_decr" do
    @cache.set("some-key", "10", 1.hour, true)
    assert_equal "10", @cache.get("some-key")
    assert_equal 9, @cache.async_decr("some-key").sync.value
    assert_equal 9, @cache.get("some-key")
  end

  test "returns duplicate of value" do
    @cache.set("key", [[:a, :b], :c])
    @cache.get("key").first.shift

    assert_equal [[:a, :b], :c], @cache.local["key"]
    assert_equal [[:a, :b], :c], @cache.get("key")
  end

  test "returns duplicate of value (async)" do
    @cache.set("key", [[:a, :b], :c])
    @cache.async_get("key").sync.value.first.shift

    assert_equal [[:a, :b], :c], @cache.local["key"]
    assert_equal [[:a, :b], :c], @cache.get("key")
  end
end
