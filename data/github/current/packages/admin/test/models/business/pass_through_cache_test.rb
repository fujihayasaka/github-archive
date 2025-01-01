# typed: true
# frozen_string_literal: true

require "test_helper"

class PassThroughCacheTest < GitHub::TestCase
  include GitHub::LoggerHelper

  setup do
    enable_cache_storage
    reset_cache
    @cache = Business::PassThroughCache.new("test", Time.now.to_i, 1)
  end

  teardown do
    disable_cache_storage
  end

  context "#values" do
    test "passes through value when disabled" do
      cache = Business::PassThroughCache.new("test", Time.now.to_i, disabled: true)
      cache.set("test", [1, 2])
      assert_equal ["3"], cache.values("test") { ["3"] }
    end

    test "passes through value and updates cache if cached does not exist" do
      assert_nil @cache.get("test")
      assert_equal %w[1 2], @cache.values("test") { %w[1 2] }
      assert_equal %w[1 2], @cache.get("test")
    end

    test "returns cached value if cached exists" do
      @cache.set("test", [1, 2])
      assert_equal %w[1 2], @cache.values("test") { ["3"] }
    end

    test "ignores cached value and does not set cache when skip_cache" do
      @cache.set("test", [1, 2])
      assert_equal ["3"], @cache.values("test", skip_cache: true) { ["3"] }
      assert_equal %w[1 2], @cache.get("test")
    end

    test "stores large number of values in multiple cache keys" do
      values = (1..65000).map { |i| "#{i}00000" }
      assert_equal values, @cache.values("test") { values }
      assert_equal values, @cache.get("test")
    end

    test "cached results don't affect other cache instances" do
      cache = Business::PassThroughCache.new("test", Time.now.to_i, 2)
      @cache.set("test", [1, 2])
      assert_equal ["3"], cache.values("test") { ["3"] }
    end

    test "does not store data when key is locked" do
      @cache.lock! 5.seconds, key: "test" do
        assert_equal ["3"], @cache.values("test") { ["3"] }
      end
      assert_nil @cache.get("test")
    end
  end

  context "#ids" do
    test "passes through value when disabled" do
      cache = Business::PassThroughCache.new("test", Time.now.to_i, disabled: true)
      cache.set("test", [1, 2])
      assert_equal [3], cache.ids("test") { [3] }
    end

    test "passes through value and updates cache if cached does not exist" do
      assert_nil @cache.get("test")
      assert_equal [1, 2], @cache.ids("test") { [1, 2] }
      assert_equal [1, 2], @cache.ids("test") { [3] }
      assert_equal [1, 2], @cache.get("test", :int)
    end

    test "stores large number of values" do
      values = (1..65000).map { |i| "#{i}00000".to_i }
      assert_equal values, @cache.ids("test") { values }
      assert_equal values, @cache.ids("test") { values }
      assert_equal values, @cache.get("test", :int)
    end

    test "converts results to int" do
      @cache.set("test", %w[1 2], :int)
      assert_equal [1, 2], @cache.ids("test") { [3] }
    end
  end

  context "seed" do
    test "stores values for a specific seed" do
      cache1 = Business::PassThroughCache.new("test", 1, disabled: true)
      cache2 = Business::PassThroughCache.new("test", 2, disabled: true)
      cache1.set("test", ["foo"])
      assert_equal ["foo"], cache1.get("test")
      assert_nil cache2.get("test")
    end
  end

  context "set" do
    test "logs large values using GitHub::Logger" do
      expected_keys = {
        "exception.type": "Business::PassThroughCache::LargeCacheSetError",
        cache_key: "test",
        cache_set_size: 500_000 * 4 - 1,
        cache_set_type: "string",
        value_count: 500_000
      }
      assert_logged(**expected_keys) do
        @cache.set("test", ["foo"] * 500_000)
      end

      expected_keys = {
        "exception.type": "Business::PassThroughCache::LargeCacheSetError",
        cache_key: "test",
        cache_set_size: 500_000 * 8,
        cache_set_type: "int",
        value_count: 500_000
      }
      assert_logged(**expected_keys) do
        @cache.set("test", [1] * 500_000, :int)
      end
    end
  end

  context "ValueCoder" do
    test "encodes and decodes values" do
      expected = [%w[a b], "a,b"]
      coder = Business::PassThroughCache::ValueCoder.new
      assert_equal expected[1], coder.encode(expected[0])
      assert_equal expected[0], coder.decode(expected[1])
    end
  end

  context "IntValueCoder" do
    test "encodes and decodes values" do
      expected = [1, 1000, 1234567890]
      coder = Business::PassThroughCache::IntValueCoder.new
      encoded = coder.encode(expected)
      assert_equal expected, coder.decode(encoded)
    end
  end
end
