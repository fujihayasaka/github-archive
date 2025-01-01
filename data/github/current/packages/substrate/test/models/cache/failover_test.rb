# typed: true
# frozen_string_literal: true

require "test_helper"
require "github/cache"

class FakeFailoverCache < GitHub::Cache::Fake
  include GitHub::Cache::Failover

  def options
    { server_failure_limit: 2 }
  end
end

class GitHubCacheFailoverMixinTest < GitHub::TestCase
  setup do
    @cache = FakeFailoverCache.new
    @cache.allow = /.*/
  end

  context "#get" do
    test "transparently deletes cache entries that can't be unmarshalled" do
      @cache.store["some-key"] = "\x04\bo:\tThisClassDoesNotExistAndNeverWill\x00"

      @cache.get("some-key")
      assert_equal false, @cache.store.has_key?("some-key")
    end

    test "treats non-marshallable cache entries as missing" do
      @cache.store["some-key"] = "\x04\bo:\tThisClassDoesNotExistAndNeverWill\x00"

      assert_nil(@cache.get("some-key"))
    end

    test "treats legacy marshal cache entries as missing" do
      @cache.store["some-key"] = Marshal.dump("some-string")
      assert_nil(@cache.get("some-key"))
    end
  end

  context "#async_get" do
    test "transparently deletes cache entries that can't be unmarshalled" do
      @cache.store["some-key"] = "\x04\bo:\tThisClassDoesNotExistAndNeverWill\x00"

      @cache.async_get("some-key").sync
      assert_equal false, @cache.store.has_key?("some-key")
    end

    test "treats non-marshallable cache entries as missing" do
      @cache.store["some-key"] = "\x04\bo:\tThisClassDoesNotExistAndNeverWill\x00"

      assert_equal(false, @cache.async_get("some-key").sync.exist?)
    end

    test "treats legacy marshal cache entries as missing" do
      @cache.store["some-key"] = Marshal.dump("some-string")
      assert_equal(false, @cache.async_get("some-key").sync.exist?)
    end
  end

  context "#get_multi" do
    test "transparently deletes cache entries that can't be unmarshalled" do
      @cache.store["some-key"] = "\x04\bo:\tThisClassDoesNotExistAndNeverWill\x00"
      @cache.store["other-key"] = GitHub::Cache::Codec.pack("value")

      @cache.get_multi(%w[some-key other-key])
      assert_equal false, @cache.store.has_key?("some-key")
    end

    test "treats non-marshallable cache entries as missing" do
      @cache.store["some-key"] = "\x04\bo:\tThisClassDoesNotExistAndNeverWill\x00"
      @cache.store["other-key"] = GitHub::Cache::Codec.pack("value")

      assert_equal({ "other-key" => "value" }, @cache.get_multi(%w[some-key other-key]))
    end

    test "loads keys individually if loading them together fails with an ignorable error" do
      GitHub::Cache::Fake.any_instance.expects(:get_multi).once.with(%w[some-key other-key], false).raises(Memcached::ActionQueued)
      GitHub::Cache::Fake.any_instance.expects(:get_multi).once.with(["some-key"], false).returns({ "some-key" => "foo" })
      GitHub::Cache::Fake.any_instance.expects(:get_multi).once.with(["other-key"], false).returns({})

      result = @cache.get_multi(%w[some-key other-key])
      assert_equal({ "some-key" => "foo" }, result)
    end

    test "returns an empty result if loading always fails with an ignorable error" do
      GitHub::Cache::Fake.any_instance.expects(:get_multi).times(3).raises(Memcached::ActionQueued)

      result = @cache.get_multi(%w[some-key other-key])
      assert_equal({}, result)
    end

    test "transparently deletes cache entries for legacy marshal" do
      @cache.store["some-key"] = Marshal.dump("some-string")
      @cache.store["other-key"] = GitHub::Cache::Codec.pack("value")

      @cache.get_multi(%w[some-key other-key])
      assert_equal false, @cache.store.has_key?("some-key")
      assert_equal true, @cache.store.has_key?("other-key")
    end

    test "retries loads on retriable failures" do
      GitHub::Cache::Fake.any_instance.expects(:get_multi).times(3).with(%w[some-key other-key], false).raises(Memcached::ReadFailure)
      GitHub::Cache::Fake.any_instance.expects(:get_multi).once.with(["some-key"], false).returns({ "some-key" => "foo" })
      GitHub::Cache::Fake.any_instance.expects(:get_multi).once.with(["other-key"], false).returns({})

      result = @cache.get_multi(%w[some-key other-key])
      assert_equal({ "some-key" => "foo" }, result)
    end

  end

  context "#async_get_multi" do
    test "transparently deletes cache entries that can't be unmarshalled" do
      @cache.store["some-key"] = "\x04\bo:\tThisClassDoesNotExistAndNeverWill\x00"
      @cache.store["other-key"] = GitHub::Cache::Codec.pack("value")

      @cache.async_get_multi(%w[some-key other-key]).sync
      assert_equal false, @cache.store.has_key?("some-key")
    end

    test "treats non-marshallable cache entries as missing" do
      @cache.store["some-key"] = "\x04\bo:\tThisClassDoesNotExistAndNeverWill\x00"
      @cache.store["other-key"] = GitHub::Cache::Codec.pack("value")

      assert_equal({ "other-key" => "value" }, @cache.async_get_multi(%w[some-key other-key]).sync)
    end

    test "loads keys individually if loading them together fails with an ignorable error" do
      GitHub::Cache::Fake.any_instance.expects(:async_get_multi).once.with(%w[some-key other-key], false).returns(Promise.new.tap { |p| p.reject(Memcached::ActionQueued.new) })
      GitHub::Cache::Fake.any_instance.expects(:async_get).once.with("some-key", false).returns(Promise.resolve(::GitHub::Cache::FakeResponse.new(key: "some-key", value: "foo", exists: true)))
      GitHub::Cache::Fake.any_instance.expects(:async_get).once.with("other-key", false).returns(Promise.resolve(::GitHub::Cache::FakeResponse.new(key: "other-key", value: nil, exists: false)))

      result = @cache.async_get_multi(%w[some-key other-key]).sync
      assert_equal({ "some-key" => "foo" }, result)
    end

    test "returns an empty result if loading always fails with an ignorable error" do
      GitHub::Cache::Fake.any_instance.expects(:async_get_multi).once.returns(Promise.new.tap { |p| p.reject(Memcached::ActionQueued.new) })
      GitHub::Cache::Fake.any_instance.expects(:async_get).times(2).returns(Promise.new.tap { |p| p.reject(Memcached::ActionQueued.new) })

      result = @cache.async_get_multi(%w[some-key other-key]).sync
      assert_equal({}, result)
    end

    test "transparently deletes cache entries for legacy marshal" do
      @cache.store["some-key"] = Marshal.dump("some-string")
      @cache.store["other-key"] = GitHub::Cache::Codec.pack("value")

      @cache.async_get_multi(%w[some-key other-key]).sync
      assert_equal false, @cache.store.has_key?("some-key")
      assert_equal true, @cache.store.has_key?("other-key")
    end

    test "retries loads on retriable failures" do
      GitHub::Cache::Fake.any_instance.expects(:async_get_multi).times(3).with(%w[some-key other-key], false).returns(Promise.new.tap { |p| p.reject(Memcached::ReadFailure.new) })
      GitHub::Cache::Fake.any_instance.expects(:async_get).once.with("some-key", false).returns(Promise.resolve(::GitHub::Cache::FakeResponse.new(key: "some-key", value: "foo", exists: true)))
      GitHub::Cache::Fake.any_instance.expects(:async_get).once.with("other-key", false).returns(Promise.resolve(::GitHub::Cache::FakeResponse.new(key: "other-key", value: nil, exists: false)))

      result = @cache.async_get_multi(%w[some-key other-key]).sync
      assert_equal({ "some-key" => "foo" }, result)
    end

  end
end
