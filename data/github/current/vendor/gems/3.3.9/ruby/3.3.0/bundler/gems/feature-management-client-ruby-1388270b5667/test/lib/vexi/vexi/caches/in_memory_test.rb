# frozen_string_literal: true
# typed: true

require "test_helper"
require "vexi/caches/in_memory"

class Vexi::Caches::InMemoryTest < Minitest::Test
  extend T::Sig

  def setup
    @inMemoryCache = Vexi::Caches::InMemory.new
  end

  def test_mget_retrieves_cached_items
    Zache.any_instance.expects(:get).with("key1").returns({ item: "item1" })
    Zache.any_instance.expects(:get).with("key2").returns({ item: "item2" })
    Zache.any_instance.expects(:get).with("key3").raises(RuntimeError.new("Key not found"))

    result = @inMemoryCache.mget(["key1", "key2", "key3"])

    assert_equal([{ item: "item1" }, { item: "item2" }], result)
  end

  def test_mset_stores_cached_items_with_provided_lifetime
    lifetime = 1337

    Zache.any_instance.expects(:put).with("key1", { item: "item1" }, lifetime: lifetime)
    Zache.any_instance.expects(:put).with("key2", { item: "item2" }, lifetime: lifetime)

    @inMemoryCache.mset({
      "key1" => { item: "item1" },
      "key2" => { item: "item2" },
    }, lifetime)
  end

  def test_get_retrieves_cached_items
    Zache.any_instance.expects(:get).with("key1").returns({ item: "item1" })
    Zache.any_instance.expects(:get).with("key2").returns({ item: "item2" })
    Zache.any_instance.expects(:get).with("key3").raises(RuntimeError.new("Key not found"))

    result1 = @inMemoryCache.get("key1")
    result2 = @inMemoryCache.get("key2")
    result3 = @inMemoryCache.get("key3")

    assert_equal({ item: "item1" }, result1)
    assert_equal({ item: "item2" }, result2)
    assert_equal(nil, result3)
  end

  def test_set_stores_cached_items_with_provided_lifetime
    lifetime = 1337

    Zache.any_instance.expects(:put).with("key1", { item: "item1" }, lifetime: lifetime)
    Zache.any_instance.expects(:put).with("key2", { item: "item2" }, lifetime: lifetime)

    @inMemoryCache.set("key1", { item: "item1" }, lifetime)
    @inMemoryCache.set("key2", { item: "item2" }, lifetime)
  end
end
