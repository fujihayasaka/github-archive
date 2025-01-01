# typed: true
# frozen_string_literal: true

require "test_helper"
require "explore_feed/feeds/kv"

class Conduit::KVBackedCacheTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
  end

  context "#get_or_set" do
    context "when there is no value in the cache" do
      test "it sets and returns the result of the block" do
        actual_result = Conduit::KVBackedCache.get_or_set_for(@user) { "expected-result" }

        assert_equal actual_result, "expected-result"
      end

      test "it emits a cache miss metric" do
        actual_result = Conduit::KVBackedCache.get_or_set_for(@user) { "expected-result" }

        assert_dogstats_increment(1, "conduit_feed.cache.miss")
      end
    end

    context "when there is a value in the cache" do
      test "it does not execute the block and returns the cached value" do
        Conduit::KVBackedCache.get_or_set_for(@user) { "cached-result" }

        actual_result = Conduit::KVBackedCache.get_or_set_for(@user) do
          raise "did not expect block to be evaluated"
        end

        assert_equal actual_result, "cached-result"
      end

      test "it emits a cache hit metric" do
        Conduit::KVBackedCache.get_or_set_for(@user) { "cached-result" }

        Conduit::KVBackedCache.get_or_set_for(@user) { "expected-result" }

        assert_dogstats_increment(1, "conduit_feed.cache.hit")
      end
    end

    context "when the result of the block is larger than 64KB" do
      test "emits a metric and reports exception" do
        too_big_str = "x" * (64.kilobytes)
        Failbot
          .expects(:report)
          .with(
            instance_of(Conduit::KVBackedCache::CacheableBodySizeExceededError),
            bytesize: too_big_str.bytesize
          ).once

        Conduit::KVBackedCache.get_or_set_for(@user) { too_big_str }

        assert_dogstats_increment(1, "conduit_feed.cache.exceeded")
      end
    end

    test "keys by user" do
      @secondary_user = create(:user)
      Conduit::KVBackedCache.get_or_set_for(@secondary_user) { "cached-result" }

      actual_result = Conduit::KVBackedCache.get_or_set_for(@user) { "expected-result" }

      assert_equal actual_result, "expected-result"
    end

    test "sets expiry for 10 minutes" do
      Conduit::KVBackedCache.get_or_set_for(@user) { "cached-result" }

      Timecop.travel(11.minutes.from_now) do
        actual_result = Conduit::KVBackedCache.get_or_set_for(@user) { "expected-result" }

        assert_equal actual_result, "expected-result"
      end
    end

    context "when the result from the KV store contains an unavailable error" do
      test "it reports the cache as unavailable but does not fail" do
        # rubocop:todo GitHub/DoNotUseGlobalKv
        Feeds::KV.store.stubs(:get).returns(GitHub::Result.new { raise GitHub::KV::UnavailableError })
        # rubocop:enable GitHub/DoNotUseGlobalKv

        actual_result = Conduit::KVBackedCache.get_or_set_for(@user) { "expected-result" }

        assert_equal actual_result, "expected-result"
        assert_failbot_report(GitHub::KV::UnavailableError)
      end
    end

    context "when setting in the KV store errors" do
      test "it reports the cache as unavailable but does not fail" do
        Feeds::KV.store.stubs(:set).raises(GitHub::KV::UnavailableError) # rubocop:todo GitHub/DoNotUseGlobalKv

        actual_result = Conduit::KVBackedCache.get_or_set_for(@user) { "expected-result" }

        assert_equal actual_result, "expected-result"
        assert_failbot_report(GitHub::KV::UnavailableError)
      end
    end
  end

  context "invalidate_for" do
    test "it removes the value associated with a user" do
      Conduit::KVBackedCache.get_or_set_for(@user) { "cached-result" }

      Conduit::KVBackedCache.invalidate_for(@user)

      actual_result = Conduit::KVBackedCache.get_or_set_for(@user) { "expected-result" }
      assert_equal actual_result, "expected-result"
    end

    context "when deleting from the KV store errors" do
      test "it returns a useful error" do
        Feeds::KV.store.stubs(:del).raises(GitHub::KV::UnavailableError) # rubocop:todo GitHub/DoNotUseGlobalKv

        assert_raises Conduit::KVBackedCache::CacheUnavailableError do
          Conduit::KVBackedCache.invalidate_for(@user)
        end
      end
    end
  end

  def assert_failbot_report(clazz)
    assert_equal 1, Failbot.reports.size, "expected at least one Failbot report"
    assert_equal clazz.to_s, Failbot.exception_classname_from_hash(Failbot.reports.last)
  end
end
