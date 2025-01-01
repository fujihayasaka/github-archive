# typed: strict
# frozen_string_literal: true

require "test_helper"

class Repositories::RedisTest < GitHub::TestCase

  TEST_KEY = "test_key"
  TEST_VALUE = "test_value"
  FALLBACK_VALUE = "fallback_value"

  setup do
    # Clean up before each test
    Repositories::Redis.del(keys: [TEST_KEY])
  end

  teardown do
    # Clean up after each test
    Repositories::Redis.del(keys: [TEST_KEY])
  end

  context "#set!" do
    test "returns true if set is successful" do
      assert Repositories::Redis.set!(key: TEST_KEY, value: TEST_VALUE, px: 10.seconds.in_milliseconds)
      assert_equal TEST_VALUE, Repositories::Redis.get!(key: TEST_KEY)
    end

    test "return false if set is not successful" do
      # `:xx => true`: Only set the key if it already exist.
      refute Repositories::Redis.set!(key: TEST_KEY, value: TEST_VALUE, px: 10.seconds.in_milliseconds, xx: true)
      assert_nil Repositories::Redis.get!(key: TEST_KEY)
    end

    test "raises error if set fails" do
      ::Redis.any_instance.stubs(:set).raises(::Redis::ConnectionError)

      assert_raises(::Redis::ConnectionError) do
        Repositories::Redis.set!(key: TEST_KEY, value: TEST_VALUE, px: 10.seconds.in_milliseconds)
      end
    end
  end

  context "#set" do
    test "returns true if set is successful" do
      assert Repositories::Redis.set(key: TEST_KEY, value: TEST_VALUE, px: 10.seconds.in_milliseconds)
      assert_equal TEST_VALUE, Repositories::Redis.get!(key: TEST_KEY)
    end

    test "return false if set is not successful" do
      # `:xx => true`: Only set the key if it already exist.
      refute Repositories::Redis.set(key: TEST_KEY, value: TEST_VALUE, px: 10.seconds.in_milliseconds, xx: true)
      assert_nil Repositories::Redis.get!(key: TEST_KEY)
    end

    test "returns false if set fail" do
      ::Redis.any_instance.stubs(:set).raises(::Redis::ConnectionError)

      refute Repositories::Redis.set(key: TEST_KEY, value: TEST_VALUE, px: 10.seconds.in_milliseconds)
      assert_nil Repositories::Redis.get!(key: TEST_KEY)
    end
  end

  context "#get!" do
    test "returns value if get is successful" do
      Repositories::Redis.set!(key: TEST_KEY, value: TEST_VALUE, px: 10.seconds.in_milliseconds)
      assert_equal TEST_VALUE, Repositories::Redis.get!(key: TEST_KEY)
    end

    test "returns nil if key is not set" do
      assert_nil Repositories::Redis.get!(key: TEST_KEY)
    end

    test "raises error if get fails" do
      ::Redis.any_instance.stubs(:get).raises(::Redis::ConnectionError)

      assert_raises(::Redis::ConnectionError) do
        Repositories::Redis.get!(key: TEST_KEY)
      end
    end
  end

  context "#get" do
    test "returns value if get is successful" do
      Repositories::Redis.set!(key: TEST_KEY, value: TEST_VALUE, px: 10.seconds.in_milliseconds)
      assert_equal TEST_VALUE, Repositories::Redis.get!(key: TEST_KEY)
    end

    context "redis failure" do
      test "returns nil if no fallback" do
        ::Redis.any_instance.stubs(:get).raises(::Redis::ConnectionError)

        assert_nil Repositories::Redis.get(key: TEST_KEY)
      end

      test "returns fallback result" do
        ::Redis.any_instance.stubs(:get).raises(::Redis::ConnectionError)

        assert_equal FALLBACK_VALUE, Repositories::Redis.get(key: TEST_KEY, fallback: FALLBACK_VALUE)
      end

      test "returns fallback block result" do
        ::Redis.any_instance.stubs(:get).raises(::Redis::ConnectionError)

        assert_equal FALLBACK_VALUE, Repositories::Redis.get(key: TEST_KEY, fallback: -> { FALLBACK_VALUE })
      end
    end
  end

  context "#del!" do
    test "returns number of deleted keys" do
      Repositories::Redis.set!(key: TEST_KEY, value: TEST_VALUE, px: 10.seconds.in_milliseconds)
      assert_equal 1, Repositories::Redis.del!(keys: [TEST_KEY])
    end

    test "raises error if it fails" do
      ::Redis.any_instance.stubs(:del).raises(::Redis::ConnectionError)

      assert_raises(::Redis::ConnectionError) do
        Repositories::Redis.del!(keys: [TEST_KEY])
      end
    end
  end

  context "#del" do
    test "returns number of deleted keys" do
      Repositories::Redis.set!(key: TEST_KEY, value: TEST_VALUE, px: 10.seconds.in_milliseconds)
      assert_equal 1, Repositories::Redis.del(keys: [TEST_KEY])
    end

    test "don't raise errors" do
      ::Redis.any_instance.stubs(:del).raises(::Redis::ConnectionError)

      assert_nil Repositories::Redis.del(keys: [TEST_KEY])
    end
  end

  context "#mutex" do
    test "return a GitHub::Redis::ConcurrencySafeMutex" do
      assert_instance_of GitHub::Redis::ConcurrencySafeMutex, Repositories::Redis.mutex(key: TEST_KEY, timeout_sec: 10.seconds)
    end
  end
end
